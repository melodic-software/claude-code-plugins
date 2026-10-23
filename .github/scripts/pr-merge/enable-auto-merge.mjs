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
// - No person turned its auto-merge off: the newest auto-merge-disabled event
//   by a user account keeps it off until a person turns it on again.
// - A verifier pass at the head just read. It is read last, only for a pull
//   request every other rule would arm or keep armed, and how depends on the
//   run (verifyFor):
//   - an event run (the issue lane, a person's edit, unlabel or ready) looks
//     the head's own PASS or PASS-NOTES up by exact artifact name
//     (headPassVerify, the same lookup and rule as ci-status's merge-queue
//     check, merge-holds.mjs verdictHold): 2 to 4 lookups and a run read;
//   - the scheduled run and a hand-started one ask pr-merge's own reader (pythonVerify,
//     babysit_verify_evidence.py `evidence`), which also refuses a FAIL at
//     the head, an earlier FAIL not cleared and FAILs at merge.max-verify-fails
//     or more heads, sharing one artifact listing and run cache in the run.
//   An event run arms on the pass alone: it does not see a FAIL at the head
//   beside a re-run's pass, an earlier FAIL, the cap, or a spec changed since
//   the judgment, and it leaves an armed pull request armed. The next reader
//   run disarms such a one. The merge queue's ci-status checks the pass again
//   at the head it merges, whatever a push after arming does.
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
//   EVENT_NAME           the run's event; `schedule` reads with the full reader
//   MAX_VERIFY_FAILS     merge.max-verify-fails (default: the reader's)
//   BABYSIT_VERIFY_GH_TOKEN  the job's GITHUB_TOKEN, for the Actions reads
//   BABYSIT_VERIFY_*, BABYSIT_RUN_CACHE  the reader's saved listing, head-ref
//                        map and run cache, as the gate's
//   GITHUB_API_URL
import { spawnSync } from "node:child_process";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import { headRefDigest } from "../pr-verify/write-verdict.mjs";
import { readHoldPaths } from "../work-resolve-issue/report-outcome.mjs";
import { BODY_HOLD, pathHold, verdictHold, vetoers } from "./merge-holds.mjs";

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
        id number isDraft isCrossRepository headRefOid headRefName body
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

// The head's own PASS or PASS-NOTES, looked up by exact artifact name with and
// without the head-branch digest, as ci-status does in the merge queue, under
// the Actions token: one lookup per name until one holds a pass verdictHold
// counts, one run read per unexpired artifact found. The answer is a report shaped
// like the reader's.
export function headPassVerify(actions, repo) {
  const verify = async ({ number, headRefOid: head, headRefName: ref }) => {
    const digest = headRefDigest(String(ref ?? ""));
    const records = [];
    for (const verdict of ["pass", "pass-notes"]) {
      for (const name of [`pr-verify-${number}-${head}-${verdict}`, `pr-verify-${number}-${head}-${verdict}-${digest}`]) {
        const listed = await actions("GET", `/repos/${repo}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100`);
        if (!Array.isArray(listed?.artifacts)) {
          throw new Error(`the ${name} artifacts did not read`);
        }
        for (const artifact of listed.artifacts) {
          const id = artifact?.workflow_run?.id;
          if (artifact?.name === name && artifact.expired === false && Number.isSafeInteger(id)) {
            records.push({ name, verdict, run: await actions("GET", `/repos/${repo}/actions/runs/${id}`) });
          }
        }
        if (verdictHold(records, repo) === null) {
          return { refusal: null, head };
        }
      }
    }
    return { refusal: "verify:missing", head };
  };
  return Object.assign(verify, { mode: "head-pass" });
}

// The gate's own reader, one process per pull request; the run shares its
// artifact listing, head-ref map and run cache through the BABYSIT_* files.
export function pythonVerify(env) {
  const verify = async ({ number, headRefOid: head }) => {
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY];
    if (env.MAX_VERIFY_FAILS) {
      args.push("--max-fails", String(env.MAX_VERIFY_FAILS));
    }
    const done = spawnSync("python3", [...args, String(number), head], { encoding: "utf8", env, timeout: 240_000 });
    if (done.status !== 0) {
      throw new Error(`babysit_verify_evidence.py exited ${done.status ?? done.signal}: ${String(done.stderr ?? "").trim().split("\n").at(-1)}`);
    }
    return JSON.parse(String(done.stdout).trim().split("\n").at(-1));
  };
  return Object.assign(verify, { mode: "reader" });
}

// The scheduled run and a hand-started one, which a person starts to retry a
// pull request that looks stuck, read with the full reader; every other event
// run with the head-pass lookup.
export const READER_EVENTS = Object.freeze(["schedule", "workflow_dispatch"]);
export function verifyFor(env, actions) {
  return READER_EVENTS.includes(env.EVENT_NAME) ? pythonVerify(env) : headPassVerify(actions, env.GITHUB_REPOSITORY);
}
// Reader time per run: past it, the rest of the pull requests are left for
// the next run rather than cut off by the step's timeout (judgment, inside
// the step's 10 minutes).
const VERIFY_BUDGET_MS = 7 * 60_000;

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
  const vetoed = pathHold(detail.files, holdPaths) ?? discussionHold(detail);
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

export async function main({ env = process.env, github, actions, verify } = {}) {
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
    actions ??= createGitHub({ token: env.BABYSIT_VERIFY_GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    verify ??= verifyFor(env, actions);
    const pulls = await listPulls(github, repo[1], repo[2]);
    const deadline = Date.now() + VERIFY_BUDGET_MS;
    let failed = 0;
    for (const pull of pulls) {
      let { action, reason } = decide(pull, { bot: slug, humanGated, holdPaths });
      let detail = null;
      if (action === "read") {
        try {
          const variables = { owner: repo[1], name: repo[2], number: pull.number };
          detail = (await github("POST", "/graphql", { query: DETAIL_QUERY, variables }))?.data?.repository?.pullRequest ?? null;
          if (detail !== null) {
            detail = { ...detail, files: await changedFiles(github, `${repo[1]}/${repo[2]}`, pull.number) };
          }
        } catch (error) {
          console.log(`enable-auto-merge: #${pull.number} discussion did not read: ${escapeCommand(error?.message ?? error)}`);
        }
        ({ action, reason } = decide(pull, { bot: slug, humanGated, holdPaths }, detail));
      }
      if (action === "verify" && pull.autoMergeRequest != null && verify.mode === "head-pass") {
        ({ action, reason } = { action: "none", reason: "already armed; the next reader run checks its verdict" });
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
