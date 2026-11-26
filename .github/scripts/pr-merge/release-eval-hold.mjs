#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, paginate } from "../lib/github-client.mjs";
import { loadTrustedList, trustedListPath } from "../lib/trusted-actors.mjs";
import { bodyHolds, fromRest, LANES_APP_LOGIN, vetoers } from "./merge-holds.mjs";

export const LABEL = "do-not-merge";
export const RELEASES_PER_RUN = 5;
export const EVAL_REASON = "eval";
const RECORD = /^<!-- eval-pair verdict=no-loss validity=VALID head=([0-9a-f]{40}) -->$/;
const RUN = /^<!-- eval-pair-run id=([1-9][0-9]{0,19}) -->$/;
const COMPARE_TITLE = /^eval-compare pr=([1-9][0-9]{0,9}) head=([0-9a-f]{40})(?: target=plugins\/([A-Za-z0-9][A-Za-z0-9._-]*)\/?)?$/;
const EVAL_TEXT = /^plugins\/([A-Za-z0-9._-]+)\/(?:skills|agents|context)\//;
const PLUGIN_FILE = /^plugins\/([A-Za-z0-9._-]+)\//;
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

export const markers = (body, pattern) => [...ownLines(body)].map((line) => pattern.exec(line)?.[1]).filter((value) => value !== undefined);

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
 * What a run read from GET actions/runs/{id} vouches for, { pr, head, plugin },
 * when it is a completed, successful first attempt of a workflow_dispatch run
 * of COMPARE_WORKFLOW on `defaultBranch` of `repo` with a compare run name;
 * else null. `plugin` is null for a name that carries no target. A re-run of failed jobs skips the dispatcher check and re-samples an
 * arm, so only attempt 1 counts. The run name comes from the dispatch inputs,
 * which the runs API does not return.
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
    run.conclusion !== "success" ||
    run.run_attempt !== 1
  ) {
    return null;
  }
  const title = COMPARE_TITLE.exec(String(run.display_title ?? ""));
  return title === null || !/^[0-9a-f]{40}$/.test(String(run.head_sha)) ? null : { pr: Number(title[1]), head: title[2], plugin: title[3] ?? null };
}

/**
 * The plugins whose skills/, agents/ or context/ files a pull request changes,
 * or, when it changes none, every plugin it changes any file of, sorted, from
 * GET pulls/{n}/files (a rename counts both paths); null when the list holds
 * fewer files than `changedFiles`, as a list cut short does.
 */
export function evalPlugins(files, changedFiles) {
  if (!Array.isArray(files) || !Number.isSafeInteger(changedFiles) || files.length < changedFiles) {
    return null;
  }
  const text = new Set();
  const any = new Set();
  for (const file of files) {
    for (const path of [file?.filename, file?.previous_filename]) {
      const name = EVAL_TEXT.exec(String(path ?? ""))?.[1];
      if (name !== undefined) {
        text.add(name);
      }
      const plugin = PLUGIN_FILE.exec(String(path ?? ""))?.[1];
      if (plugin !== undefined) {
        any.add(plugin);
      }
    }
  }
  return [...(text.size > 0 ? text : any)].sort();
}

/**
 * Whether GET compare/{run head}...{default branch tip SHA} shows the run's
 * commit on the default branch. head_branch is only a ref name, which a tag
 * can share, and a tag runs its own copy of the workflow; the tip is read from
 * refs/heads/ first, since a bare name resolves to a tag before a branch.
 */
export const onDefaultBranch = (compare) => compare?.status === "identical" || compare?.status === "ahead";

export const RECORD_JOB = "Compare Record";
export const JOBS_PER_RUN = 100;

/**
 * Whether GET actions/runs/{id}/jobs shows RECORD_JOB completed with success,
 * read from one complete page. A skipped job also reads as success in the
 * run's conclusion, so a run whose jobs all skipped (a dispatch on a tag,
 * where compare-prepare's ref gate skips everything after it) vouches for
 * nothing; RECORD_JOB runs only after the dispatcher check, both arms and
 * the verdict passed.
 */
export function recordJobRan(answer) {
  const jobs = Array.isArray(answer?.jobs) ? answer.jobs : null;
  if (jobs === null || !Number.isSafeInteger(answer.total_count) || answer.total_count > jobs.length) {
    return false;
  }
  const named = jobs.filter((job) => job?.name === RECORD_JOB);
  return named.length === 1 && named[0].status === "completed" && named[0].conclusion === "success";
}

export const CANNOT_START_JOB = "Compare Cannot Start";
export const CANNOT_START_CAUSES = Object.freeze(["compare-refused"]);

/**
 * The cause a compare run recorded for not starting, from one complete page
 * of GET actions/runs/{id}/jobs, or null. The workflow names its one
 * `${CANNOT_START_JOB}: <cause>` job from compare-prepare's own output, so
 * only the run itself writes the cause.
 */
export function cannotStartCause(answer) {
  const jobs = Array.isArray(answer?.jobs) ? answer.jobs : null;
  if (jobs === null || !Number.isSafeInteger(answer.total_count) || answer.total_count > jobs.length) {
    return null;
  }
  const named = jobs.filter((job) => typeof job?.name === "string" && job.name.startsWith(CANNOT_START_JOB));
  if (named.length !== 1 || named[0].status !== "completed" || named[0].conclusion !== "success" || recordJobRan(answer)) {
    return null;
  }
  const cause = named[0].name.slice(`${CANNOT_START_JOB}: `.length);
  return named[0].name === `${CANNOT_START_JOB}: ${cause}` && CANNOT_START_CAUSES.includes(cause) ? cause : null;
}

const counts =(comment, humans, vouched, number) => {
  if (byHuman(comment, humans)) {
    return true;
  }
  const id = citedRun(comment);
  const run = id === null ? undefined : vouched.get(id);
  return run !== undefined && run.pr === number && run.head === markers(comment.body, RECORD)[0];
};

export function heldAt(events) {
  const times = (events ?? []).filter((event) => event?.event === "labeled" && event.label?.name === LABEL).map((event) => String(event.created_at ?? ""));
  return times.length === 0 ? null : times.sort().at(-1);
}

export function decide({ pull, comments, reviews = [], events, humans, vouched = new Map(), cannotStart = null }) {
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
  if (newest !== undefined && newest.heads[0] === head) {
    return { release: true, record: newest.comment, head };
  }
  if (cannotStart?.head === head && CANNOT_START_CAUSES.includes(cannotStart.cause)) {
    return { release: true, cannotStart, head };
  }
  return keep(newest === undefined ? "no-record" : "record-head-mismatch");
}

export const releasedComment = (head, record) =>
  `${releasedMarker(head, record.id)}\nThe \`${LABEL}\` hold waited only on eval evidence (\`reason=${EVAL_REASON}\`), and a VALID no-loss eval-pair record for \`${head}\` was posted ${citedRun(record) === null ? "by a listed human" : `by compare run ${citedRun(record)}, read back as this pull request's`}: ${record.html_url}. pr-merge removed \`${LABEL}\`. To hold again, add the label back with a new \`pr-hold\` reason line.`;

export const cannotStartMarker = (head, { cause, runs }) => `<!-- eval-hold-released head=${head} cannot-start=${cause} run=${runs.map((run) => run.id).join(",")} -->`;

export const cannotStartComment = (head, cannotStart) =>
  `${cannotStartMarker(head, cannotStart)}\nThe \`${LABEL}\` hold waited only on eval evidence (\`reason=${EVAL_REASON}\`), and for every plugin whose skill, agent or context text this pull request changes (or, when it changes none, every plugin it changes), the newest compare run for \`${head}\`, read back as this pull request's, recorded that it cannot start (\`${cannotStart.cause}\`): ${cannotStart.runs.map((run) => `\`${run.plugin}\` ${run.html_url}`).join(", ")}. Such a pull request merges first: after it merges, its affected cases run in a suite run on the default branch, and a FAIL reverts it (docs/review/evals.md). pr-merge removed \`${LABEL}\`. To hold again, add the label back with a new \`pr-hold\` reason line.`;

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
  `Held for the before-and-after eval that #${issueNumber} needs: this pull request closes #${issueNumber}, which carries \`${EVAL_GATED_LABEL}\`. The pr-merge release step lifts this hold when an eval-pair record for the current head is posted, or when a compare run for the current head records that it cannot start.\n\n<!-- pr-hold reason=${EVAL_REASON} -->`;

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

export const COMPARE_RUNS_LIST = `/actions/workflows/${COMPARE_WORKFLOW.split("/").at(-1)}/runs?event=workflow_dispatch&per_page=100`;

const namedPull = (run) => {
  const title = COMPARE_TITLE.exec(String(run?.display_title ?? ""));
  return title === null ? null : Number(title[1]);
};

export const COMPARE_RUN_PAGES = 10;

const createdAt = (run) => (typeof run?.created_at === "string" ? run.created_at : "");

function compareRunLister(github, repo) {
  const runs = [];
  let pages = 0;
  let last = false;
  let failed = false;
  const reaches = (since) => runs.length > 0 && createdAt(runs.at(-1)) !== "" && createdAt(runs.at(-1)) < since;
  return async (since) => {
    while (!failed && !last && !reaches(since) && pages < COMPARE_RUN_PAGES) {
      pages += 1;
      try {
        const batch = (await github("GET", `/repos/${repo}${COMPARE_RUNS_LIST}&page=${pages}`))?.workflow_runs;
        if (!Array.isArray(batch)) {
          throw new Error(`page ${pages} held no workflow_runs`);
        }
        runs.push(...batch);
        last = batch.length < 100;
      } catch (error) {
        failed = true;
        console.log(`release-eval-hold: the compare runs did not list: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    return { runs, complete: !failed && (last || reaches(since)) };
  };
}

async function readAll(github, repo, number, humans, runsGitHub = github, listRuns = compareRunLister(runsGitHub, repo)) {
  const base = `/repos/${repo}/issues/${number}`;
  const comments = await paginate(github, `${base}/comments`);
  const early = mayRelease(comments, humans);
  if (early === "no-eval-hold") {
    return { early };
  }
  const events = await paginate(github, `${base}/events`);
  const since = heldAt(events);
  const listed = since === null ? { runs: [], complete: false } : await listRuns(since);
  const named = listed.runs.filter((run) => namedPull(run) === number);
  if (early !== null && named.length === 0) {
    return { early };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  const defaultBranch = pull?.base?.repo?.default_branch;
  const vouched = await readRuns(runsGitHub, repo, comments, defaultBranch);
  if (since !== null && !listed.complete) {
    console.log(`release-eval-hold: #${number} the compare runs since ${since} run past ${COMPARE_RUN_PAGES} pages; no cannot-start run counts`);
  }
  const plugins = listed.complete && named.length > 0 ? await readEvalPlugins(github, repo, number, pull?.changed_files) : null;
  const cannotStart = plugins === null ? null : await readCannotStart(runsGitHub, repo, named, vouched, since, pull?.head?.sha, defaultBranch, plugins);
  return { pull, comments, events, reviews, vouched, cannotStart };
}

async function readEvalPlugins(github, repo, number, changedFiles) {
  let files;
  try {
    files = await paginate(github, `/repos/${repo}/pulls/${number}/files`, 30);
  } catch (error) {
    console.log(`release-eval-hold: #${number} files did not read: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
  const plugins = evalPlugins(files, changedFiles);
  if (plugins === null) {
    console.log(`release-eval-hold: #${number} files listed ${files.length} of ${changedFiles}; no cannot-start run counts`);
  }
  return plugins;
}

async function readTip(github, repo, defaultBranch) {
  try {
    const tip = (await github("GET", `/repos/${repo}/git/ref/heads/${encodeURIComponent(defaultBranch)}`))?.object?.sha;
    return /^[0-9a-f]{40}$/.test(String(tip)) ? tip : null;
  } catch (error) {
    console.log(`release-eval-hold: the ${defaultBranch} tip did not read: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
}

async function readBack(github, repo, run, defaultBranch, tip, judge, missing) {
  const vouch = runVouches(run, repo, defaultBranch);
  if (vouch === null) {
    return null;
  }
  let jobs;
  try {
    jobs = await github("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=all&per_page=${JOBS_PER_RUN}`);
  } catch (error) {
    console.log(`release-eval-hold: run ${run.id}'s jobs did not read: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
  const verdict = judge(jobs);
  if (verdict === null) {
    console.log(`release-eval-hold: run ${run.id} ${missing}`);
    return null;
  }
  let compare;
  try {
    compare = await github("GET", `/repos/${repo}/compare/${run.head_sha}...${tip}`);
  } catch (error) {
    console.log(`release-eval-hold: run ${run.id}'s commit did not compare with ${defaultBranch}: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
  return onDefaultBranch(compare) ? { ...vouch, verdict } : null;
}

async function readRuns(github, repo, comments, defaultBranch) {
  const ids = [...new Set(comments.map(citedRun).filter((id) => id !== null).reverse())].slice(0, RUNS_PER_PULL);
  const vouched = new Map();
  if (ids.length === 0 || typeof defaultBranch !== "string") {
    return vouched;
  }
  const tip = await readTip(github, repo, defaultBranch);
  if (tip === null) {
    return vouched;
  }
  for (const id of ids) {
    let run;
    try {
      run = await github("GET", `/repos/${repo}/actions/runs/${id}`);
    } catch (error) {
      console.log(`release-eval-hold: run ${id} did not read: ${escapeCommand(error?.message ?? error)}`);
      continue;
    }
    const vouch = await readBack(github, repo, { ...run, id }, defaultBranch, tip, (jobs) => (recordJobRan(jobs) ? true : null), `did not run ${RECORD_JOB} to success`);
    if (vouch !== null) {
      vouched.set(id, { pr: vouch.pr, head: vouch.head });
    }
  }
  return vouched;
}

async function readCannotStart(github, repo, named, vouched, since, head, defaultBranch, plugins) {
  if (!/^[0-9a-f]{40}$/.test(String(head)) || typeof defaultBranch !== "string" || plugins.length === 0) {
    return null;
  }
  const atHead = named
    .map((run) => ({ run, title: COMPARE_TITLE.exec(String(run.display_title)) }))
    .filter(({ run, title }) => title?.[2] === head && createdAt(run) >= since)
    .sort((a, b) => createdAt(b.run).localeCompare(createdAt(a.run)));
  const tip = await readTip(github, repo, defaultBranch);
  if (tip === null) {
    return null;
  }
  const runs = [];
  for (const plugin of plugins) {
    const [newest, ...older] = atHead.filter(({ title }) => (title[3] ?? plugin) === plugin);
    if (newest === undefined || newest.title[3] !== plugin) {
      console.log(`release-eval-hold: no compare run at ${head} since the hold names ${plugin} as its target`);
      return null;
    }
    const { run } = newest;
    if (vouched.has(String(run.id)) || !/^[1-9][0-9]{0,19}$/.test(String(run.id))) {
      return null;
    }
    const vouch = await readBack(github, repo, run, defaultBranch, tip, cannotStartCause, `recorded no cause it cannot start`);
    if (vouch === null || vouch.head !== head || vouch.plugin !== plugin) {
      return null;
    }
    const loss = await olderLoss(github, repo, older.map((entry) => entry.run));
    if (loss !== null) {
      console.log(`release-eval-hold: run ${run.id} cannot start, but ${loss}`);
      return null;
    }
    runs.push({ plugin, cause: vouch.verdict, id: String(run.id), html_url: run.html_url });
  }
  return { head, cause: runs[0].cause, runs };
}

export const VERDICT_JOB = "Compare Verdict";
export const LOSS_READS = 5;

/**
 * Whether one complete page of GET actions/runs/{id}/jobs shows VERDICT_JOB
 * ending other than success or skipped: compare-verdict.mjs fails it on a
 * LOSS or VOID and posts no record. An unreadable or partial answer counts.
 */
export function verdictFailed(answer) {
  const jobs = Array.isArray(answer?.jobs) ? answer.jobs : null;
  if (jobs === null || !Number.isSafeInteger(answer.total_count) || answer.total_count > jobs.length) {
    return true;
  }
  return jobs.some((job) => job?.name === VERDICT_JOB && job.conclusion !== "success" && job.conclusion !== "skipped");
}

async function olderLoss(github, repo, older) {
  const unsettled = older.find((run) => run.status !== "completed" || run.run_attempt !== 1);
  if (unsettled !== undefined) {
    return `run ${unsettled.id} at the same head is still going or was re-run`;
  }
  const failed = older.filter((run) => run.conclusion !== "success");
  if (failed.length > LOSS_READS) {
    return `${failed.length} runs at the same head failed, past ${LOSS_READS} to read`;
  }
  for (const run of failed) {
    let jobs;
    try {
      jobs = await github("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=all&per_page=${JOBS_PER_RUN}`);
    } catch (error) {
      return `run ${run.id}'s jobs did not read: ${escapeCommand(error?.message ?? error)}`;
    }
    if (verdictFailed(jobs)) {
      return `run ${run.id} at the same head failed its ${VERDICT_JOB}`;
    }
  }
  return null;
}

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
    const { humans } = loadTrustedList(trustedListPath(env, env.TRUSTED_ACTORS_PATH));
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    runsGitHub ??= env.RUNS_TOKEN ? createGitHub({ token: env.RUNS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }) : github;
    const holds = await holdEvalGated(github, repo, humans);
    summary(`release-eval-hold: eval-gated=${holds.gated} holds-added=${holds.added} not-held=${holds.kept} failed=${holds.failed}`);
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${LABEL}&sort=created&direction=asc`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    const counts = { kept: 0, failed: 0 };
    const released = [];
    const listRuns = compareRunLister(runsGitHub, repo);
    for (const { number } of held) {
      if (released.length >= RELEASES_PER_RUN) {
        console.log(`release-eval-hold: #${number} kept: ${RELEASES_PER_RUN} released this run`);
        counts.kept += 1;
        continue;
      }
      try {
        const read = await readAll(github, repo, number, humans, runsGitHub, listRuns);
        const result = read.early === undefined ? decide({ ...read, humans }) : { release: false, reason: read.early };
        if (!result.release) {
          console.log(`release-eval-hold: #${number} kept: ${result.reason}`);
          counts.kept += 1;
          continue;
        }
        const { head, record, cannotStart } = result;
        const marker = record ? releasedMarker(head, record.id) : cannotStartMarker(head, cannotStart);
        const since = heldAt(read.events);
        const explained = read.comments.some(
          (comment) => comment?.user?.login === bot && String(comment.created_at ?? "") >= since && [...ownLines(comment.body)].includes(marker),
        );
        const base = `/repos/${repo}/issues/${number}`;
        if (!explained) {
          if (!(await stands(github, repo, number, head))) {
            console.log(`release-eval-hold: #${number} kept: moved-before-comment`);
            counts.kept += 1;
            continue;
          }
          await github("POST", `${base}/comments`, { body: record ? releasedComment(head, record) : cannotStartComment(head, cannotStart) });
        }
        if (!(await stands(github, repo, number, head))) {
          console.log(`release-eval-hold: #${number} kept: moved-before-removal`);
          counts.kept += 1;
          continue;
        }
        await github("DELETE", `${base}/labels/${LABEL}`);
        released.push(number);
        if (!record) {
          console.log(`release-eval-hold: #${number} released head=${head} cannot-start=${cannotStart.cause} run=${cannotStart.runs.map((run) => run.html_url).join(",")}`);
          continue;
        }
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
