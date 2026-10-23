#!/usr/bin/env node
// enable-auto-merge.mjs: turns on GitHub's native auto-merge for the lanes
// App's open pull requests into main, and turns it off on one that now carries
// a hold. No model. pr-merge.yml's enable-auto-merge job runs it when the issue
// lane finishes, when a listed human edits, unlabels or readies a pull
// request, and on the schedule, which arms any the other events missed.
//
// A pull request is armed only when all of these hold:
// - The lanes App opened it (merge.agent-identity), into main, from a branch
//   of this repository, and it is not a draft.
// - Its body opens with `Closes #<issue>`: a `Refs:` pull request is merged
//   by a person (report-outcome.mjs).
// - It carries no hold: no `do-not-merge` and no human-gated label (the
//   tracker's role label, `needs-human` by default), and no body hold
//   (merge-holds.mjs).
// - No member vetoes it (merge-holds.mjs). ci-status fails on both holds too,
//   so one added after arming stops the merge queue rather than waiting for
//   this job's next run.
// - Its head changes no hold path: the merge lane's denied paths
//   (report-outcome.readHoldPaths), read against the files, renamed-from paths
//   included, that the head changes now, since a push after report-outcome
//   wrote its Hold: line can add one. The rule is merge-holds.pathHold, which
//   ci-status also runs on every lanes App pull request event and merge
//   group, so a push after arming is held without waiting for this job.
// - Its head changes no cost path, unless its body links the owner's cost
//   decision: merge-holds.costHold and costDecision, which ci-status runs too.
// - No person turned its auto-merge off: the newest auto-merge-disabled event
//   by a user account keeps it off until a person turns it on again.
// - pr-merge's gate would take its verifier verdict at the head just read:
//   babysit_verify_evidence.py `evidence` refuses nothing (verifyHold), so a
//   pr-verify PASS or PASS-NOTES stands at that head, no FAIL is at it, no
//   earlier FAIL is uncleared, FAILs sit at fewer than merge.max-verify-fails
//   heads, and the spec is unchanged and trusted. Only the scheduled run and
//   a hand-started one read it (READER_EVENTS), last, for a pull request
//   every other rule would arm or keep armed, sharing one artifact listing
//   and run cache in the run. An event run (the issue lane, a person's edit,
//   unlabel or ready) never arms and reads no verdict: it only disarms on a
//   hold, so a pull request waits up to one scheduled interval to be armed.
//   ci-status disarms an armed lanes App pull request on each push to its
//   head, so a new head is armed only after the reader judges it, and in the
//   merge queue it checks the pass again at the head it merges
//   (merge-holds.mjs verdictHold).
// Arming passes the head just read as expectedHeadOid, so a push in between
// fails the arm rather than arming a head nobody read. An armed pull request
// that fails any rule is disarmed. While merge.report-only is true it reports
// each decision and writes nothing.
//
// Environment:
//   GH_TOKEN             the lane App token (contents and pull-requests write)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   REPORT_ONLY          `false` writes; anything else reports only
//   LANES_BOT_LOGIN      merge.agent-identity, an App bot login
//   TRACKER_CONFIG       the base .work-item-tracker.json, for the human-gated
//                        label (default .base/.work-item-tracker.json)
//   RESOLVED_CONFIG      the resolve-config output, for the hold paths
//   TRUSTED_ACTORS       the base trusted-actors.json, for the owner of a cost
//                        decision (default .base/.github/standards/trusted-actors/trusted-actors.json)
//   EVENT_NAME           the run's event; only READER_EVENTS read verdicts and arm
//   BABYSIT_VERIFY_*, BABYSIT_RUN_CACHE  the reader's Actions token (the
//                        job's GITHUB_TOKEN), saved listing, head-ref map and
//                        run cache, as the gate's
//   GITHUB_API_URL
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import { readHoldPaths } from "../work-resolve-issue/report-outcome.mjs";
import { BODY_HOLD, costDecision, costHold, humansOf, pathHold, vetoers } from "./merge-holds.mjs";

export { BODY_HOLD, HUMAN_VETO } from "./merge-holds.mjs";

const REPO = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/;
const SHA = /^[0-9a-f]{40}$/;
const BOT_LOGIN = /^([a-z0-9][a-z0-9-]*)\[bot\]$/;
// babysit_merge_policy.MERGE_HOLD_LABELS, plus the human-gated label.
const HOLD_LABELS = Object.freeze(["do-not-merge"]);
const CLOSES = /^Closes #[1-9][0-9]*\r?$/;
// 100 pull requests a page; more than this many open is a listing the run
// stops on rather than one it reads only part of.
const MAX_PAGES = 10;
// Changed files read per pull request, 100 a page; more is a head the run
// does not arm on.
const MAX_FILE_PAGES = 3;
const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";

export const PULLS_QUERY = `query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: "main", first: 100, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id number isDraft isCrossRepository headRefOid baseRefOid body
        author { __typename login }
        labels(first: 100) { totalCount nodes { name } }
        autoMergeRequest { enabledAt }
      }
    }
  }
}`;
// One candidate's discussion. The newest 100 of each, and more than that is
// a discussion the run does not arm on rather than one it reads only part of.
export const DETAIL_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(last: 100) { totalCount nodes { author { __typename login } body createdAt authorAssociation } }
      reviews(last: 100) { totalCount nodes { author { __typename login } body submittedAt authorAssociation } }
      reviewThreads(last: 100) {
        totalCount
        nodes { comments(last: 100) { totalCount nodes { author { __typename login } body createdAt authorAssociation } } }
      }
      timelineItems(itemTypes: [AUTO_MERGE_DISABLED_EVENT], last: 1) { nodes { ... on AutoMergeDisabledEvent { actor { __typename login } } } }
    }
  }
}`;
export const ARM_MUTATION = `mutation($id: ID!, $head: GitObjectID!) {
  enablePullRequestAutoMerge(input: { pullRequestId: $id, mergeMethod: SQUASH, expectedHeadOid: $head }) {
    pullRequest { autoMergeRequest { enabledAt } }
  }
}`;
export const DISARM_MUTATION = `mutation($id: ID!) {
  disablePullRequestAutoMerge(input: { pullRequestId: $id }) { clientMutationId }
}`;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// Why `pull` must not be armed, or null when it may be.
export function holdReason(pull, humanGated) {
  const labels = pull.labels?.nodes ?? [];
  if (!(pull.labels?.totalCount <= labels.length)) {
    return "its labels could not all be read";
  }
  const names = new Set(labels.map((label) => String(label?.name).toLowerCase()));
  const label = [...HOLD_LABELS, humanGated].find((name) => names.has(name.toLowerCase()));
  if (label !== undefined) {
    return `it carries ${label}`;
  }
  const body = String(pull.body ?? "");
  if (BODY_HOLD.test(body)) {
    return "its body holds it";
  }
  if (!CLOSES.test(body.split("\n")[0])) {
    return "its body does not open with Closes #<issue>";
  }
  return null;
}

const whole = (connection) => Array.isArray(connection?.nodes) && connection.totalCount <= connection.nodes.length;

// Why the discussion `detail` (DETAIL_QUERY's pullRequest) holds it, or null.
export function discussionHold(detail) {
  const threads = detail?.reviewThreads;
  if (![detail?.comments, detail?.reviews, threads].every(whole) || !threads.nodes.every((thread) => whole(thread?.comments))) {
    return "its comments could not all be read";
  }
  const items = [...detail.comments.nodes, ...detail.reviews.nodes, ...threads.nodes.flatMap((thread) => thread.comments.nodes)].map((item) => ({
    login: item?.author?.login,
    isUser: item?.author?.__typename === "User",
    association: item?.authorAssociation,
    at: String(item?.submittedAt ?? item?.createdAt ?? ""),
    body: String(item?.body ?? ""),
  }));
  const vetoes = vetoers(items);
  return vetoes.length ? `${vetoes.join(", ")} asked not to merge it` : null;
}

// The trusted-actor list's people; an unreadable list names none, so no cost
// decision clears.
function trustedHumans(env) {
  try {
    const { actors } = JSON.parse(readFileSync(env.TRUSTED_ACTORS || ".base/.github/standards/trusted-actors/trusted-actors.json", "utf8"));
    return humansOf(actors);
  } catch {
    return new Set();
  }
}

async function changedFiles(github, slug, number) {
  const paths = [];
  for (let page = 1; page <= MAX_FILE_PAGES; page += 1) {
    const rows = await github("GET", `/repos/${slug}/pulls/${number}/files?per_page=100&page=${page}`);
    if (!Array.isArray(rows)) {
      return null;
    }
    for (const row of rows) {
      paths.push(String(row?.filename), ...(row?.previous_filename ? [String(row.previous_filename)] : []));
    }
    if (rows.length < 100) {
      return paths;
    }
  }
  return null;
}

// Why the gate's verifier `evidence` (babysit_verify_evidence.py's report)
// keeps a pull request at `head` from merging, or null when it allows it.
export function verifyHold(evidence, head) {
  if (evidence === null || typeof evidence !== "object" || !("refusal" in evidence)) {
    return "its verifier verdict could not be read";
  }
  if (evidence.head !== head) {
    return "its verifier verdict was read at another head";
  }
  return evidence.refusal === null ? null : `pr-merge's gate refuses its verifier verdict (${escapeCommand(evidence.refusal)})`;
}

// The gate's own reader, one process per pull request; the run shares its
// artifact listing, head-ref map and run cache through the BABYSIT_* files.
export function pythonVerify(env) {
  const verify = async ({ number, headRefOid: head, baseRefOid: base }) => {
    if (!SHA.test(String(base))) {
      throw new Error("its base commit is not a commit SHA");
    }
    // --base-sha: the gate's FAIL cap, the lower of the base's and main's.
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY, "--base-sha", base];
    const done = spawnSync("python3", [...args, String(number), head], { encoding: "utf8", env, timeout: VERIFY_TIMEOUT_MS });
    if (done.status !== 0) {
      throw new Error(`babysit_verify_evidence.py exited ${done.status ?? done.signal}: ${String(done.stderr ?? "").trim().split("\n").at(-1)}`);
    }
    return JSON.parse(String(done.stdout).trim().split("\n").at(-1));
  };
  return verify;
}

// The runs that read the verifier verdict and so may arm: the schedule, and a
// hand-started run, which a person starts to retry a pull request that looks
// stuck.
export const READER_EVENTS = Object.freeze(["schedule", "workflow_dispatch"]);
// The reader's per pull request limit, and when the run stops starting one:
// a read started at the budget ends by VERIFY_BUDGET_MS + VERIFY_TIMEOUT_MS,
// 9 minutes, inside the step's 10 (pr-merge.yml), so no read is cut off and
// the rest of the pull requests are left for the next run.
export const VERIFY_TIMEOUT_MS = 4 * 60_000;
export const VERIFY_BUDGET_MS = 5 * 60_000;

// What to do with one listed pull request: { action: arm | disarm | none, reason }.
// `detail` is its discussion; undefined means not read yet, and an arm or a
// keep then waits on it (action `read`). Its `verify` is the gate's verifier
// evidence; absent, an arm or a keep waits on it (action `verify`).
export function decide(pull, { bot, humanGated, holdPaths = null }, detail) {
  if (pull.author?.__typename !== "Bot" || pull.author.login !== bot) {
    return { action: "none", reason: "not the lanes App's" };
  }
  const armed = pull.autoMergeRequest != null;
  const held =
    pull.isDraft !== false
      ? "it is a draft"
      : pull.isCrossRepository !== false
        ? "it is from another repository"
        : !SHA.test(String(pull.headRefOid))
          ? "its head is not a commit SHA"
          : holdReason(pull, humanGated);
  if (held !== null) {
    return { action: armed ? "disarm" : "none", reason: held };
  }
  if (detail === undefined) {
    return { action: "read", reason: "its discussion is not read yet" };
  }
  if (detail === null) {
    return { action: "none", reason: "its discussion did not read" };
  }
  const vetoed = pathHold(detail.files, holdPaths) ?? costHold(detail.files, detail.costDecision) ?? discussionHold(detail);
  if (vetoed !== null) {
    return { action: armed ? "disarm" : "none", reason: vetoed };
  }
  if (!armed && detail.timelineItems?.nodes?.at(-1)?.actor?.__typename === "User") {
    return { action: "none", reason: "a person turned its auto-merge off" };
  }
  if (!("verify" in detail)) {
    return { action: "verify", reason: "its verifier verdict is not read yet" };
  }
  const unverified = verifyHold(detail.verify, pull.headRefOid);
  if (unverified !== null) {
    return { action: armed ? "disarm" : "none", reason: unverified };
  }
  return armed ? { action: "none", reason: "already armed" } : { action: "arm", reason: "no hold" };
}

async function listPulls(github, owner, name) {
  const pulls = [];
  let after = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const data = (await github("POST", "/graphql", { query: PULLS_QUERY, variables: { owner, name, after } }))?.data;
    const connection = data?.repository?.pullRequests;
    if (!Array.isArray(connection?.nodes)) {
      throw new Error("the open pull request listing did not read");
    }
    pulls.push(...connection.nodes);
    if (!connection.pageInfo?.hasNextPage) {
      return pulls;
    }
    after = connection.pageInfo.endCursor;
  }
  throw new Error(`more than ${MAX_PAGES * 100} open pull requests into main`);
}

export async function main({ env = process.env, github, verify } = {}) {
  try {
    const repo = REPO.exec(env.GITHUB_REPOSITORY ?? "");
    if (!repo) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("enable-auto-merge: the lanes kill switch stops this run; nothing read or armed");
      return 0;
    }
    const slug = BOT_LOGIN.exec(env.LANES_BOT_LOGIN ?? "")?.[1];
    if (slug === undefined) {
      throw new Error("LANES_BOT_LOGIN is not an App bot login");
    }
    const write = env.REPORT_ONLY === "false";
    const humanGated = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json");
    const holdPaths = readHoldPaths(env.RESOLVED_CONFIG ?? "");
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    verify ??= pythonVerify(env);
    const reads = READER_EVENTS.includes(env.EVENT_NAME);
    const pulls = await listPulls(github, repo[1], repo[2]);
    const deadline = Date.now() + VERIFY_BUDGET_MS;
    let failed = 0;
    for (const pull of pulls) {
      let { action, reason } = decide(pull, { bot: slug, humanGated, holdPaths });
      let detail = null;
      if (action === "read" && !reads && pull.autoMergeRequest == null) {
        ({ action, reason } = { action: "none", reason: "only a scheduled or hand-started run arms it, on the gate's verifier verdict" });
      }
      if (action === "read") {
        try {
          const variables = { owner: repo[1], name: repo[2], number: pull.number };
          detail = (await github("POST", "/graphql", { query: DETAIL_QUERY, variables }))?.data?.repository?.pullRequest ?? null;
          if (detail !== null) {
            const files = await changedFiles(github, `${repo[1]}/${repo[2]}`, pull.number);
            const decision = costHold(files, null) ? await costDecision(github, repo[0], pull.number, pull.body, trustedHumans(env)) : null;
            detail = { ...detail, files, costDecision: decision };
          }
        } catch (error) {
          console.log(`enable-auto-merge: #${pull.number} discussion did not read: ${escapeCommand(error?.message ?? error)}`);
        }
        ({ action, reason } = decide(pull, { bot: slug, humanGated, holdPaths }, detail));
      }
      if (action === "verify" && !reads) {
        ({ action, reason } =
          pull.autoMergeRequest != null
            ? { action: "none", reason: "already armed; the next scheduled run checks its verifier verdict" }
            : { action: "none", reason: "only a scheduled or hand-started run arms it, on the gate's verifier verdict" });
      } else if (action === "verify" && Date.now() > deadline) {
        ({ action, reason } = { action: "none", reason: "no time left in this run to read its verifier verdict" });
      } else if (action === "verify") {
        let evidence = null;
        try {
          evidence = await verify(pull);
        } catch (error) {
          console.log(`enable-auto-merge: #${pull.number} verifier verdict did not read: ${escapeCommand(error?.message ?? error)}`);
        }
        ({ action, reason } = decide(pull, { bot: slug, humanGated, holdPaths }, { ...detail, verify: evidence }));
      }
      if (action === "none") {
        if (reason !== "not the lanes App's") {
          console.log(`enable-auto-merge: #${pull.number} left: ${reason}`);
        }
        continue;
      }
      if (!write) {
        console.log(`enable-auto-merge: #${pull.number} would ${action} (report-only): ${reason}`);
        continue;
      }
      try {
        if (action === "arm") {
          await github("POST", "/graphql", { query: ARM_MUTATION, variables: { id: pull.id, head: pull.headRefOid } });
          console.log(`enable-auto-merge: #${pull.number} armed at ${pull.headRefOid}`);
        } else {
          await github("POST", "/graphql", { query: DISARM_MUTATION, variables: { id: pull.id } });
          console.log(`enable-auto-merge: #${pull.number} disarmed: ${reason}`);
        }
      } catch (error) {
        failed += 1;
        console.log(`::error title=enable-auto-merge::#${pull.number} ${action}: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=enable-auto-merge::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
