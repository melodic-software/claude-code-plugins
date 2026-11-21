#!/usr/bin/env node
// release-eval-hold.mjs: takes `do-not-merge` off an open pull request whose
// hold waits only on eval evidence of no loss, once the eval-pair record for
// its current head is posted by a listed human, or by github-actions[bot] from
// a compare run of pr-run-plugin-evals.yml that this script reads back: a
// successful workflow_dispatch run on the default branch whose run name
// (`eval-compare pr=<n> head=<sha>`, set from its inputs) names this pull
// request and the record's head. The comment's author alone counts for
// nothing, since any workflow can post as github-actions[bot] (owner decision
// Q136: https://github.com/melodic-software/claude-code-plugins/issues/17854).
// No model. The hold convention is in docs/contracts/loop-lane/README.md
// (Cross-lane PR hold).
//
// The head and the label are read again before the comment and before the
// removal. The comment comes first, carrying RELEASED_MARKER, so a failed
// removal is retried by the next run without a second comment. At most
// RELEASES_PER_RUN a run. Each pull request logs one line,
// `release-eval-hold: #<n> released head=<sha> record=<url> wait-minutes=<m>`
// or `release-eval-hold: #<n> kept: <reason>`, and the run ends with
// `release-eval-hold: held=<h> released=<r> kept=<k> failed=<f>`.
//
// Environment:
//   GH_TOKEN             the lane token (reads, the comment, the label)
//   RUNS_TOKEN           a token with actions: read for the cited runs
//                        (default GH_TOKEN), which
//                        https://docs.github.com/en/rest/actions/workflow-runs#get-a-workflow-run
//                        requires
//   GITHUB_REPOSITORY    owner/repo
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   KILL_SWITCH          `proceed` to run
//   LANES_BOT_LOGIN      the lanes App's login (default LANES_APP_LOGIN)
//   GITHUB_STEP_SUMMARY  receives the run line
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { bodyHolds, fromRest, LANES_APP_LOGIN, vetoers } from "./merge-holds.mjs";

export const LABEL = "do-not-merge";
export const RELEASES_PER_RUN = 5;
export const EVAL_REASON = "eval";
const RECORD = /^<!-- eval-pair verdict=no-loss validity=VALID head=([0-9a-f]{40}) -->$/;
const RUN = /^<!-- eval-pair-run id=([1-9][0-9]{0,19}) -->$/;
const COMPARE_TITLE = /^eval-compare pr=([1-9][0-9]{0,9}) head=([0-9a-f]{40})$/;
export const COMPARE_WORKFLOW = ".github/workflows/pr-run-plugin-evals.yml";
export const WORKFLOW_LOGIN = "github-actions[bot]";
export const RUNS_PER_PULL = 3;
const HOLD = /^<!-- pr-hold reason=([a-z0-9][a-z0-9-]{0,63}) -->$/;
const HOLD_PREFIX = "<!-- pr-hold";
const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const QUOTE = /^ {0,3}>/;
const REPO = /^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/;

export const EVAL_GATED_LABEL = "eval-gated";
export const OPEN_PULL_PAGES = 20;
export const OPEN_PULLS_QUERY = `query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, first: 50, after: $cursor, orderBy: { field: CREATED_AT, direction: ASC }) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        labels(first: 100) { nodes { name } }
        closingIssuesReferences(first: 10) { nodes { number repository { nameWithOwner } labels(first: 100) { nodes { name } } } }
      }
    }
  }
}`;

export const releasedMarker = (head, recordId) => `<!-- eval-hold-released head=${head} record=${recordId} -->`;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The lines of `body` outside a fenced code block and a block quote, as written.
export function* ownLines(body) {
  let fence = "";
  for (const line of String(body ?? "").split(/\r\n|\r|\n/)) {
    const marker = FENCE.exec(line);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && line.slice(marker[0].length).trim() === "") {
        fence = "";
      }
      continue;
    }
    if (marker) {
      fence = marker[1];
      continue;
    }
    if (!QUOTE.test(line)) {
      yield line;
    }
  }
}

// Every capture of `pattern` on a line of its own in `body`.
export const markers = (body, pattern) => [...ownLines(body)].map((line) => pattern.exec(line)?.[1]).filter((value) => value !== undefined);

// A comment a listed human wrote: a User account by id, not through an App.
const byHuman = (comment, humans) =>
  comment?.user?.type === "User" && Number.isSafeInteger(comment.user.id) && humans.has(comment.user.id) && comment.performed_via_github_app == null;

const byLanesApp = (comment) => comment?.user?.type === "Bot" && comment.user.login === LANES_APP_LOGIN;

/**
 * The run id a github-actions[bot] comment cites beside its one record line,
 * or null. Citing a run proves nothing until runVouches reads it.
 */
export function citedRun(comment) {
  if (comment?.user?.type !== "Bot" || comment.user.login !== WORKFLOW_LOGIN || markers(comment.body, RECORD).length !== 1) {
    return null;
  }
  const ids = markers(comment.body, RUN);
  return ids.length === 1 ? ids[0] : null;
}

/**
 * What a run read from GET actions/runs/{id} vouches for, { pr, head }, when
 * it is a completed, successful workflow_dispatch run of COMPARE_WORKFLOW on
 * `defaultBranch` of `repo` with a compare run name; else null. The run name
 * comes from the dispatch inputs, which the runs API does not return.
 */
export function runVouches(run, repo, defaultBranch) {
  const same = (name) => typeof name === "string" && name.toLowerCase() === String(repo).toLowerCase();
  if (
    run?.path !== COMPARE_WORKFLOW ||
    run.event !== "workflow_dispatch" ||
    typeof defaultBranch !== "string" ||
    run.head_branch !== defaultBranch ||
    !same(run.repository?.full_name) ||
    !same(run.head_repository?.full_name) ||
    run.status !== "completed" ||
    run.conclusion !== "success"
  ) {
    return null;
  }
  const title = COMPARE_TITLE.exec(String(run.display_title ?? ""));
  return title === null ? null : { pr: Number(title[1]), head: title[2] };
}

/**
 * Whether `comment` is a record that counts for pull request `number`: a
 * listed human's, or a cited run's that `vouched` (run id -> { pr, head })
 * holds for this pull request and the record's head.
 */
const counts =(comment, humans, vouched, number) => {
  if (byHuman(comment, humans)) {
    return true;
  }
  const id = citedRun(comment);
  const run = id === null ? undefined : vouched.get(id);
  return run !== undefined && run.pr === number && run.head === markers(comment.body, RECORD)[0];
};

// The newest `labeled` event of LABEL, as its time, or null.
export function heldAt(events) {
  const times = (events ?? []).filter((event) => event?.event === "labeled" && event.label?.name === LABEL).map((event) => String(event.created_at ?? ""));
  return times.length === 0 ? null : times.sort().at(-1);
}

// Whether to release one pull request: { release: true, record, head } or
// { release: false, reason }. `pull` is GET pulls/{n}; `comments` the issue
// comments, `reviews` the reviews and `events` the issue events, each every
// page; `humans` the listed humans' ids (numbers).
export function decide({ pull, comments, reviews = [], events, humans, vouched = new Map() }) {
  const keep = (reason) => ({ release: false, reason });
  if (pull?.state !== "open") {
    return keep("not-open");
  }
  if (!(pull.labels ?? []).some((label) => label?.name === LABEL)) {
    return keep("no-label");
  }
  const head = pull.head?.sha;
  if (!/^[0-9a-f]{40}$/.test(String(head))) {
    return keep("head-unread");
  }
  const since = heldAt(events);
  if (since === null) {
    return keep("no-label-event");
  }
  const recent = (comments ?? []).filter((comment) => String(comment?.created_at ?? "") >= since);
  const holds = recent.flatMap((comment) => [...ownLines(comment.body)].filter((line) => line.trimStart().startsWith(HOLD_PREFIX)).map((line) => ({ comment, line })));
  if (holds.length === 0) {
    return keep("no-hold-reason");
  }
  for (const { comment, line } of holds) {
    const reason = HOLD.exec(line)?.[1];
    if (reason === undefined) {
      return keep("hold-reason-unknown");
    }
    if (reason !== EVAL_REASON) {
      return keep(`hold-reason-${reason}`);
    }
    if (!byHuman(comment, humans) && !byLanesApp(comment)) {
      return keep("hold-reason-unlisted-author");
    }
  }
  if (bodyHolds(pull.body, true)) {
    return keep("body-hold");
  }
  const vetoing = vetoers([...(comments ?? []), ...(reviews ?? [])].map(fromRest));
  if (vetoing.length > 0) {
    return keep(`member-veto-${vetoing.join(",")}`);
  }
  const newest = newestRecord(recent, humans, vouched, pull.number);
  if (newest === undefined) {
    return keep("no-record");
  }
  if (newest.heads[0] !== head) {
    return keep("record-head-mismatch");
  }
  return { release: true, record: newest.comment, head };
}

export const releasedComment = (head, record) =>
  `${releasedMarker(head, record.id)}\nThe \`${LABEL}\` hold waited only on eval evidence (\`reason=${EVAL_REASON}\`), and a VALID no-loss eval-pair record for \`${head}\` was posted ${citedRun(record) === null ? "by a listed human" : `by compare run ${citedRun(record)}, read back as this pull request's`}: ${record.html_url}. pr-merge removed \`${LABEL}\`. To hold again, add the label back with a new \`pr-hold\` reason line.`;

/**
 * A reason to stop before the remaining reads, or null. A cited run is read
 * later, so a comment citing one passes here unread.
 */
export function mayRelease(comments, humans) {
  if (!(comments ?? []).some((comment) => (byHuman(comment, humans) || byLanesApp(comment)) && markers(comment.body, HOLD).includes(EVAL_REASON))) {
    return "no-eval-hold";
  }
  return (comments ?? []).some((comment) => (byHuman(comment, humans) && markers(comment.body, RECORD).length > 0) || citedRun(comment) !== null)
    ? null
    : "no-record";
}

const newestRecord = (comments, humans, vouched = new Map(), number = undefined) =>
  comments
    .filter((comment) => counts(comment, humans, vouched, number))
    .map((comment) => ({ comment, heads: markers(comment.body, RECORD) }))
    .filter(({ heads }) => heads.length === 1)
    .sort((a, b) => String(a.comment.created_at).localeCompare(String(b.comment.created_at)))
    .at(-1);

const labelNames = (connection) => (Array.isArray(connection?.nodes) ? connection.nodes.map((node) => node?.name) : []);

/**
 * The first issue in `repo` that `pull` (an OPEN_PULLS_QUERY node) closes and
 * that carries EVAL_GATED_LABEL, as its number, or null.
 */
export function evalGatedIssue(pull, repo) {
  const own = (issue) => String(issue?.repository?.nameWithOwner).toLowerCase() === String(repo).toLowerCase();
  const nodes = Array.isArray(pull?.closingIssuesReferences?.nodes) ? pull.closingIssuesReferences.nodes : [];
  const issue = nodes.find((node) => own(node) && Number.isSafeInteger(node.number) && labelNames(node.labels).includes(EVAL_GATED_LABEL));
  return issue === undefined ? null : issue.number;
}

/**
 * Whether to hold one open pull request that closes an eval-gated issue:
 * { hold: true } or { hold: false, reason }. `pull` is GET pulls/{n};
 * `comments` the issue comments, every page; `humans` the listed humans' ids.
 * One held for eval before, by a listed human or the lanes App, is left to
 * the release and to whoever took the label off since.
 */
export function holdDecision({ pull, comments, humans }) {
  const keep = (reason) => ({ hold: false, reason });
  if (pull?.state !== "open" || pull.merged_at) {
    return keep("not-open");
  }
  if ((pull.labels ?? []).some((label) => label?.name === LABEL)) {
    return keep("labeled");
  }
  const all = comments ?? [];
  if (all.some((comment) => (byHuman(comment, humans) || byLanesApp(comment)) && markers(comment.body, HOLD).includes(EVAL_REASON))) {
    return keep("held-before");
  }
  const newest = newestRecord(all, humans);
  if (newest !== undefined && newest.heads[0] === pull.head?.sha) {
    return keep("record-at-head");
  }
  return { hold: true };
}

export const evalHoldComment = (issueNumber) =>
  `Held for the before-and-after eval that #${issueNumber} needs: this pull request closes #${issueNumber}, which carries \`${EVAL_GATED_LABEL}\`. The pr-merge release step lifts this hold when a listed human posts an eval-pair record for the current head.\n\n<!-- pr-hold reason=${EVAL_REASON} -->`;

async function evalGatedPulls(github, repo) {
  const [owner, name] = repo.split("/");
  const gated = [];
  let cursor = null;
  for (let page = 0; page < OPEN_PULL_PAGES; page += 1) {
    const answer = await github("POST", "/graphql", { query: OPEN_PULLS_QUERY, variables: { owner, name, cursor } });
    const connection = answer?.data?.repository?.pullRequests;
    if (!Array.isArray(connection?.nodes)) {
      throw new Error("the open pull requests did not read");
    }
    for (const node of connection.nodes) {
      const issue = evalGatedIssue(node, repo);
      if (issue !== null && Number.isSafeInteger(node.number) && !labelNames(node.labels).includes(LABEL)) {
        gated.push({ number: node.number, issue });
      }
    }
    if (!connection.pageInfo?.hasNextPage) {
      return gated;
    }
    cursor = connection.pageInfo.endCursor;
  }
  throw new Error(`the open pull requests run past ${OPEN_PULL_PAGES} pages`);
}

async function holdEvalGated(github, repo, humans) {
  const counts = { gated: 0, added: 0, kept: 0, failed: 0 };
  let gated;
  try {
    gated = await evalGatedPulls(github, repo);
  } catch (error) {
    counts.failed += 1;
    console.log(`::error title=release-eval-hold::${escapeCommand(error?.message ?? error)}`);
    return counts;
  }
  counts.gated = gated.length;
  for (const { number, issue } of gated) {
    try {
      const base = `/repos/${repo}/issues/${number}`;
      const comments = await paginate(github, `${base}/comments`);
      const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
      const result = holdDecision({ pull, comments, humans });
      if (!result.hold) {
        console.log(`release-eval-hold: #${number} not held: ${result.reason}`);
        counts.kept += 1;
        continue;
      }
      await github("POST", `${base}/labels`, { labels: [LABEL] }, {}, { resendOnce: true });
      await github("POST", `${base}/comments`, { body: evalHoldComment(issue) }, {}, { resendOnce: true });
      counts.added += 1;
      console.log(`release-eval-hold: #${number} held for eval: it closes eval-gated #${issue}`);
    } catch (error) {
      counts.failed += 1;
      console.log(`::error title=release-eval-hold::#${number}: ${escapeCommand(error?.message ?? error)}`);
    }
  }
  return counts;
}

// The comments first; the rest only for a pull request that may release.
async function readAll(github, repo, number, humans, runsGitHub = github) {
  const base = `/repos/${repo}/issues/${number}`;
  const comments = await paginate(github, `${base}/comments`);
  const early = mayRelease(comments, humans);
  if (early !== null) {
    return { early };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  const events = await paginate(github, `${base}/events`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  const vouched = await readRuns(runsGitHub, repo, comments, pull?.base?.repo?.default_branch);
  return { pull, comments, events, reviews, vouched };
}

/**
 * The newest RUNS_PER_PULL runs the comments cite, read back, as run id ->
 * { pr, head } for each that vouches. A run that does not read vouches for
 * nothing, so a forged id releases nothing; the next run reads it again.
 */
async function readRuns(github, repo, comments, defaultBranch) {
  const ids = [...new Set(comments.map(citedRun).filter((id) => id !== null).reverse())].slice(0, RUNS_PER_PULL);
  const vouched = new Map();
  for (const id of ids) {
    let run;
    try {
      run = await github("GET", `/repos/${repo}/actions/runs/${id}`);
    } catch (error) {
      console.log(`release-eval-hold: run ${id} did not read: ${escapeCommand(error?.message ?? error)}`);
      continue;
    }
    const vouch = runVouches(run, repo, defaultBranch);
    if (vouch !== null) {
      vouched.set(id, vouch);
    }
  }
  return vouched;
}

// Whether the head and the label still stand as decided.
async function stands(github, repo, number, head) {
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  return pull?.state === "open" && pull.head?.sha === head && (pull.labels ?? []).some((label) => label?.name === LABEL);
}

export async function main({ env = process.env, github, runsGitHub, now = Date.now } = {}) {
  const summary = (line) => {
    console.log(line);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n`);
    }
  };
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("release-eval-hold: the lanes kill switch stops this run; nothing read or removed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || LANES_APP_LOGIN;
    const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH || ".base/.github/standards/trusted-actors/trusted-actors.json");
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    runsGitHub ??= env.RUNS_TOKEN ? createGitHub({ token: env.RUNS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }) : github;
    const holds = await holdEvalGated(github, repo, humans);
    summary(`release-eval-hold: eval-gated=${holds.gated} holds-added=${holds.added} not-held=${holds.kept} failed=${holds.failed}`);
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${LABEL}&sort=created&direction=asc`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    const counts = { kept: 0, failed: 0 };
    const released = [];
    for (const { number } of held) {
      if (released.length >= RELEASES_PER_RUN) {
        console.log(`release-eval-hold: #${number} kept: ${RELEASES_PER_RUN} released this run`);
        counts.kept += 1;
        continue;
      }
      try {
        const read = await readAll(github, repo, number, humans, runsGitHub);
        const result = read.early === undefined ? decide({ ...read, humans }) : { release: false, reason: read.early };
        if (!result.release) {
          console.log(`release-eval-hold: #${number} kept: ${result.reason}`);
          counts.kept += 1;
          continue;
        }
        const { head, record } = result;
        const since = heldAt(read.events);
        const explained = read.comments.some(
          (comment) =>
            comment?.user?.login === bot &&
            String(comment.created_at ?? "") >= since &&
            [...ownLines(comment.body)].includes(releasedMarker(head, record.id)),
        );
        const base = `/repos/${repo}/issues/${number}`;
        if (!explained) {
          if (!(await stands(github, repo, number, head))) {
            console.log(`release-eval-hold: #${number} kept: moved-before-comment`);
            counts.kept += 1;
            continue;
          }
          await github("POST", `${base}/comments`, { body: releasedComment(head, record) });
        }
        if (!(await stands(github, repo, number, head))) {
          console.log(`release-eval-hold: #${number} kept: moved-before-removal`);
          counts.kept += 1;
          continue;
        }
        await github("DELETE", `${base}/labels/${LABEL}`);
        released.push(number);
        const wait = Math.round((now() - Date.parse(record.created_at)) / 60000);
        console.log(`release-eval-hold: #${number} released head=${head} record=${record.html_url} wait-minutes=${Number.isFinite(wait) ? wait : "unknown"}`);
      } catch (error) {
        counts.failed += 1;
        console.log(`::error title=release-eval-hold::#${number}: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    summary(`release-eval-hold: held=${held.length} released=${released.length} kept=${counts.kept} failed=${counts.failed}`);
    if (env.GITHUB_OUTPUT) {
      appendFileSync(env.GITHUB_OUTPUT, `released=${released.join(" ")}\n`);
    }
    return counts.failed + holds.failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=release-eval-hold::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
