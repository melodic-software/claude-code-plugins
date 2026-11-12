// The monitoring lane's reads: every source the signals need, through the
// job's own GITHUB_TOKEN and githubstatus.com, into one data object. A source
// that fails to read is recorded in `gaps` and the others still run. Every
// list is bounded, and `get` spends the run's call budget.
import { parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";
import { escalationActivity, escalationRoute, STOP_RESOLVED } from "../pr-unblock/escalation-routes.mjs";
import { HOLD_LANES, holdJob, parseBudget, parseHold, POST_MERGE_UNREADABLE_SWEEPS, STALLED_HOURS, SWEEP_MAX_AGE_MINUTES } from "./signals.mjs";
import { stepsKnown } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";

export const LIMITS = {
  prMergeRuns: 12,
  // Lane runs whose jobs the lanes App quota read lists, newest first, and the
  // jobs with a successful mint step whose annotations it reads, in all: at
  // most 1 + 10 + 1 calls, the annotations in one GraphQL query (10 REST reads
  // where it does not answer). A sample, not every mint in the window.
  laneRuns: 10,
  laneMintJobs: 10,
  inProgressRuns: 30,
  failedRuns: 12,
  failedRunPages: 5,
  // Failed scheduled work-unblock runs signal 14 reads, apart from the failed
  // runs above so their cap never hides one. The schedule is hourly, so the
  // window plus its lookback holds about 7.
  laneVariableRuns: 10,
  failedJobsPerRun: 3,
  mainFailedJobs: 5,
  mergeGroupRuns: 10,
  // pr-merge-summary artifacts read newest first: room for a held streak past
  // LISTING_HELD_SWEEPS and the sweep that listed before it.
  sweepArtifacts: 8,
  // pr-merge-post-merge-report artifacts listed in one call, newest first; a
  // fork's runs can upload under the same name, so the page is wide.
  postMergeArtifacts: 100,
  commentPages: 5,
  // Open pull requests the stalled-stop read covers, most recently updated
  // first: one GraphQL query lists the first stalledPulls with each one's
  // newest 100 comments and the open count; at most stalledCommentRounds more
  // queries read 100 older comments for every PR whose newest name no stop on
  // its head; at most stalledChecks check-run reads in all. So the source
  // spends at most 1 + 2 + 20 of CALL_BUDGET. stalledPulls covers every open
  // pull request at today's count; past it, a gap leaves signal 10 unread
  // rather than missing a stop.
  stalledPulls: 40,
  stalledCommentRounds: 2,
  stalledChecks: 20,
  // Uncarried green runs per hold lane read in one window, oldest completion
  // first, unless the lane sets its own (signals.mjs HOLD_LANES holdRuns):
  // up to holdListPages run list pages (pr-verify's and pr-merge's own 5,
  // pr-review-main's 4), then each run's jobs and the annotations of each
  // green job that prints a hold. Every lane's jobs are read in one GraphQL
  // query per 25 runs, and its annotations in one per 25 jobs. A run has one
  // green hold job (pr-verify's one of three), but pr-review-main's about 3
  // (its trigger and two review legs) and pr-merge's up to 2, so at most
  // 4 × 3 + 5 + 4 + 5 list pages, 1 + 1 + 1 + 2 + 4 + 3 + 4 list queries and
  // 1 + 1 + 1 + 2 + 4 + 9 + 7 annotation queries (67 calls, 41 of them
  // GraphQL), plus one lane-hold marker list per lane (7). A re-run, or a
  // node GraphQL does not answer, is read through REST, one call a jobs or
  // annotation read; a REST list has steps, so pr-verify and pr-review-main
  // (holdStep) read only a job whose `Note the hold` ran, and a run of theirs
  // whose GraphQL-listed hold job the annotation batch did not answer is
  // listed again through REST first. With GraphQL refused, or answering the
  // lists but not the annotations, those two lanes spend at most 7 + 150
  // list calls and one annotation read per held job, not 290 for every green
  // hold job; the other lanes'
  // 152 jobs and about 232 annotation reads put the source past
  // CALL_BUDGET at the caps either way. Past the cap, the span stops at the
  // last run read and the window is a gap.
  holdRuns: 6,
  // Run list pages of 100 per hold lane, unless the lane sets its own
  // (HOLD_LANES listPages): intake-triage listed up to 151 green runs over the
  // 7-hour created span in the 7 days to 2026-11-05. A lane with more is a
  // gap, since its oldest-created runs go unlisted.
  holdListPages: 3,
  // Held runs the carry keeps, newest first.
  holdsKept: 300,
};
// report-escalation.sh's comment for a stop routed to a failing status, one
// per activity, edited at each stop (gate-source.mjs LANE_STOPPED).
const LANE_STOPPED = /^<!-- pr-unblock:lane-stopped activity=([a-z]+(?:-[a-z]+)*) -->$/;
const STOP_FIELD = (name) => new RegExp(`^- ${name}: \`([^\`]+)\``, "m");
// clear-escalations.mjs's comment when it took off a needs-human an older run
// set (gate-source.mjs CLEARED): a reason now routed to a failing status left
// that head with no stop comment of its own.
const CLEARED = /^<!-- pr-pipeline needs-human-cleared reason=([a-z,-]+) head=([0-9a-f]{40}) -->$/;
// One GraphQL query reading one field per item under its own alias, so a
// source reads every pull request it covers in one call. The repository is
// the query's $owner and $name.
export const batchQuery = (fields) =>
  `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${fields.map((field, i) => `a${i}: ${field}`).join(" ")} } }`;
async function queryRepo(graphql, repo, query) {
  const [owner, name] = repo.split("/");
  const result = await graphql(query, { owner, name });
  if (result?.errors?.length) throw new Error(`GraphQL: ${result.errors.map((e) => e.message).join("; ")}`);
  return result?.data?.repository ?? {};
}
// GraphQL reads that stand in for REST job lists and annotation reads, so
// they spend the GraphQL limit rather than core. One query reads NODES_BATCH
// runs' check runs, or NODES_BATCH check runs' annotations, in about a second;
// check-run steps stay on REST, since a GraphQL read of 5 runs' steps timed
// out. A re-run's list stays on REST, whose filter=latest keeps only its last
// attempt's jobs.
const NODES_BATCH = 25;
const CHECK_RUNS_PAGE = 30;
const RUN_CHECK_RUNS = `query($ids: [ID!]!) { nodes(ids: $ids) { ... on WorkflowRun { databaseId runAttempt checkSuite { checkRuns(first: ${CHECK_RUNS_PAGE}, filterBy: { checkType: ALL }) { totalCount nodes { id databaseId name status conclusion } } } } } }`;
const CHECK_RUN_ANNOTATIONS = "query($ids: [ID!]!) { nodes(ids: $ids) { ... on CheckRun { databaseId annotations(first: 100) { totalCount nodes { annotationLevel title message } } } } }";
// Each id's node, in order, or null where the answer has none, an error names
// it, or the query failed: the caller reads that one through REST.
async function readNodes(graphql, query, ids) {
  const out = ids.map(() => null);
  for (let at = 0; at < ids.length; at += NODES_BATCH) {
    let result;
    try {
      result = await graphql(query, { ids: ids.slice(at, at + NODES_BATCH) });
    } catch {
      continue;
    }
    const errors = result?.errors ?? [];
    const named = errors.map((e) => (e?.path?.[0] === "nodes" && Number.isInteger(e.path[1]) ? e.path[1] : null));
    if (!Array.isArray(result?.data?.nodes) || named.includes(null)) continue;
    result.data.nodes.forEach((node, i) => {
      if (at + i < out.length && !named.includes(i)) out[at + i] = node ?? null;
    });
  }
  return out;
}
// A whole connection's nodes, or null when it is missing, cut short or holds a null.
const wholeNodes = (connection) =>
  Array.isArray(connection?.nodes) && connection.nodes.length === connection.totalCount && connection.nodes.every((n) => n !== null && typeof n === "object") ? connection.nodes : null;
const lower = (value) => (typeof value === "string" ? value.toLowerCase() : null);
// A run's check runs as the REST jobs list shapes them, oldest first, without
// steps, or null when the node does not answer for the run in full.
export function restJobs(node, run) {
  const runs = node?.databaseId === run.id && node.runAttempt === 1 ? wholeNodes(node.checkSuite?.checkRuns) : null;
  if (!runs?.length || !runs.every((c) => Number.isSafeInteger(c.databaseId) && typeof c.id === "string")) return null;
  return runs
    .map((c) => ({ id: c.databaseId, node_id: c.id, name: c.name, status: lower(c.status), conclusion: lower(c.conclusion) }))
    .sort((a, b) => a.id - b.id);
}
// A check run's annotations as REST shapes the fields the sources read, or null.
export function restAnnotations(node, job) {
  const nodes = node?.databaseId === job.id ? wholeNodes(node.annotations) : null;
  return nodes && nodes.map((a) => ({ annotation_level: lower(a.annotationLevel), title: a.title, message: a.message }));
}

// A comment connection's page, oldest first; GraphQL names a Bot without
// [bot], so its login is put back in the REST form agentIdentity uses.
const COMMENT_PAGE = "pageInfo { hasPreviousPage startCursor } nodes { author { __typename login } body createdAt updatedAt url }";
const restComment = (node) => ({
  user: { login: node.author?.__typename === "Bot" ? `${node.author.login}[bot]` : node.author?.login },
  body: node.body,
  created_at: node.createdAt,
  updated_at: node.updatedAt,
  html_url: node.url,
});
// An attempt of the activity on the head: any of its check runs but a skip,
// which a select job posts without running the activity (a stop's own
// lane-stopped, a held awaiting-human, not-applicable, or stop-resolved).
const attempted = (run) => !(run.conclusion === "neutral" && String(run.output?.title ?? "").startsWith("Skipped:"));
// A select job that finds the stop gone on its head skips stop-resolved and
// report-stop-status posts success over the failing status, which this job
// cannot read, so that skip stands for the success.
export const AUDIT_WORKFLOWS = ["maintenance-audit-test-selection", "maintenance-check-upstream-drift"];
// Pull-request and merge-group runs hold no lane token, and a merge-group
// failure is counted as an ejection instead.
const SKIP_FAILED_EVENTS = new Set(["pull_request", "merge_group"]);
// The test-suite runs hold no lane token either, and their failure annotations
// name tests, some of them for rate limits; signal 1 reads main's suite.
const SKIP_FAILED_PATHS = new Set([".github/workflows/pr-require-checks.yml", ".github/workflows/pr-test-platforms.yml"]);
const QUEUE_BRANCH = /^gh-readonly-queue\/[^/]+\/pr-(\d+)-[0-9a-f]+$/;
// Signal 14's job and the two steps of its repository variable check, as
// work-unblock.yml names them.
const WORK_UNBLOCK_PATH = ".github/workflows/work-unblock.yml";
export const PUBLISH_LANE_LEVEL_JOB = "publish-lane-level";
// That job's name, and its id as a run from before the job rename lists it.
const PUBLISH_LANE_LEVEL_NAMES = new Set(["Publish Lane Level", PUBLISH_LANE_LEVEL_JOB]);
export const VARIABLE_STEPS = new Set(["List the repository variables before the publish", "Check no other repository variable changed"]);
// Only main's own scheduled or dispatched pr-merge runs are trusted: a PR,
// fork or branch run can upload an artifact or annotation of the same name.
const TRUSTED_EVENTS = new Set(["schedule", "workflow_dispatch"]);
const PR_MERGE_PATH = ".github/workflows/pr-merge.yml";
// pr-merge's merge job by name, then by the id a run from before the job rename lists.
const MERGE_JOB = "Merge";
const MERGE_JOB_BEFORE_RENAME = "merge";
const mergeJob = (jobs) => jobs.find((j) => j.name === MERGE_JOB) ?? jobs.find((j) => j.name === MERGE_JOB_BEFORE_RENAME);
// The step name every lane workflow gives request-lane-token in token mode.
const MINT_STEP = "Request the lane token";
// Events whose run takes its workflow code from the default branch; a push
// or a dispatch counts only on main. A pull_request or review event runs a
// branch's code, which could write a notice of the same shape.
const DEFAULT_BRANCH_EVENTS = new Set(["schedule", "workflow_run", "pull_request_target", "issues", "issue_comment"]);
const MAIN_ONLY_EVENTS = new Set(["push", "workflow_dispatch"]);
const RUN_ID = /^[0-9]+$/;
// A run is read in the window it completes in, so the list reaches back to
// runs created this long before the window opened.
const RUN_LOOKBACK_HOURS = 6;
const iso = (date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");

// The artifact that carries completed runs' job reads from one run of this
// lane to the next, and its file's version: bump it whenever the fields kept
// or the rule for keeping them change.
export const JOBS_ARTIFACT = "monitor-signals-jobs";
export const JOBS_FILE = "jobs.json";
export const JOBS_VERSION = 1;
const jobsKey = (id, attempt) => `${id}:${attempt}`;
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const isTimeOrNull = (value) => value === null || (typeof value === "string" && !Number.isNaN(Date.parse(value)));
// A job with only the fields the sources read.
const slimJob = (job) => ({
  id: job.id,
  name: job.name,
  status: job.status,
  conclusion: job.conclusion,
  steps: Array.isArray(job.steps) ? job.steps.map((s) => ({ name: s?.name, number: s?.number, status: s?.status, conclusion: s?.conclusion })) : job.steps,
});

// The carried job reads by run id and attempt, or an error for any other shape.
export function parseJobsCarry(text, repo) {
  const data = JSON.parse(text);
  const entry = (e) =>
    Number.isSafeInteger(e?.id) && e.id > 0 && Number.isSafeInteger(e.attempt) && e.attempt > 0 && typeof e.updated_at === "string" && Array.isArray(e.jobs) && e.jobs.every(isObject);
  if (data?.version !== JOBS_VERSION || data.repository !== repo || !Array.isArray(data.runs) || !data.runs.every(entry)) {
    throw new Error("the carried job reads file has an unexpected shape");
  }
  return new Map(data.runs.map((e) => [jobsKey(e.id, e.attempt), e]));
}

const NO_HELD = { runs: [], from: null, through: null, scanned: [] };
const NO_EPISODES = { at: null, signals: {} };
export const jobsCarryFile = (repo, runs, held = NO_HELD, episodes = NO_EPISODES) => JSON.stringify({ version: JOBS_VERSION, repository: repo, runs, held, episodes });

// The signals' timers the same file carries, {signal: {onSince, clearSince}},
// empty when the file has none or they are older than RUN_LOOKBACK_HOURS: runs
// that kept no carry for that long say nothing about the time between. An
// error for any other shape.
export function parseEpisodeCarry(text, repo, now) {
  const data = JSON.parse(text);
  const episodes = data?.episodes ?? NO_EPISODES;
  const entry = (e) => isObject(e) && isTimeOrNull(e.onSince ?? null) && isTimeOrNull(e.clearSince ?? null);
  if (data?.repository !== repo || !isObject(episodes.signals) || !isTimeOrNull(episodes.at) || !Object.values(episodes.signals).every(entry)) {
    throw new Error("the carried signal timers have an unexpected shape");
  }
  if (episodes.at === null || now.getTime() - Date.parse(episodes.at) > RUN_LOOKBACK_HOURS * 3600_000) return {};
  return episodes.signals;
}

// The held runs the same file carries, {runs, from, through, scanned}: the
// runs, the unbroken span of completion times the lane read them over (null
// when not known, as in a file written before it carried them), and the runs
// read with no hold, {lane, runId, at} by completion time (none in a file
// written before it carried them), or an error for any other shape.
export function parseHeldCarry(text, repo) {
  const data = JSON.parse(text);
  const held = data?.held ?? NO_HELD;
  const scanned = held?.scanned ?? [];
  const scannedEntry = (h) => HOLD_LANES.some((l) => l.lane === h?.lane) && Number.isSafeInteger(h.runId) && h.runId > 0 && typeof h.at === "string" && isTimeOrNull(h.at);
  const entry = (h) => scannedEntry(h) && typeof h.url === "string" && (h.item === null || typeof h.item === "string") && typeof h.reason === "string";
  if (
    data?.repository !== repo ||
    !Array.isArray(held?.runs) ||
    !held.runs.every(entry) ||
    !isTimeOrNull(held.from) ||
    !isTimeOrNull(held.through) ||
    !Array.isArray(scanned) ||
    !scanned.every(scannedEntry)
  ) {
    throw new Error("the carried held runs have an unexpected shape");
  }
  return { runs: held.runs, from: held.from, through: held.through, scanned };
}

// `carriedJobs` is the last run's job reads (parseJobsCarry). A completed
// run's carried read is used while its listing shows the same attempt and
// updated_at, and a whole read of a completed run whose every job finished and
// listed its steps in full is kept; data.jobsCarry holds what the next run
// carries: this run's reads and hits, nothing else. `holds`, when set, is
// {rule, carried}: signals.mjs holdRule's result or the error reading it, and
// the last run's held runs (parseHeldCarry), or null when there were none or
// they were not read; data.heldCarry holds what the next run carries.
export async function collect({ get, graphql, getStatus, readArtifact, repo, now, windowStart, agentIdentity, ownRate = null, carriedJobs = new Map(), holds = null }) {
  const gaps = [];
  const jobsMemo = new Map();
  const annotationsMemo = new Map();
  const keptJobs = new Map();
  const jobsOf = async (run) => {
    if (!jobsMemo.has(run.id)) {
      const key = jobsKey(run.id, run.run_attempt);
      const final = run.status === "completed" && Number.isSafeInteger(run.run_attempt) && typeof run.updated_at === "string";
      const carried = final ? carriedJobs.get(key) : undefined;
      if (carried && carried.updated_at === run.updated_at) {
        keptJobs.set(key, carried);
        jobsMemo.set(run.id, carried.jobs);
      } else {
        const listing = await get(`/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
        const jobs = listing.jobs ?? [];
        if (
          final &&
          // An empty listing may not have settled yet, so it is never carried.
          jobs.length > 0 &&
          jobs.length === listing.total_count &&
          jobs.every((j) => j?.status === "completed" && j.conclusion != null && stepsKnown(j) && (j.run_attempt === undefined || j.run_attempt === run.run_attempt))
        ) {
          keptJobs.set(key, { id: run.id, attempt: run.run_attempt, updated_at: run.updated_at, jobs: jobs.map(slimJob) });
        }
        jobsMemo.set(run.id, jobs);
      }
    }
    return jobsMemo.get(run.id);
  };
  const annotationsOf = async (jobId) => {
    if (!annotationsMemo.has(jobId)) {
      annotationsMemo.set(jobId, (await get(`/repos/${repo}/check-runs/${jobId}/annotations?per_page=100`)) ?? []);
    }
    return annotationsMemo.get(jobId);
  };
  // Job lists read through GraphQL carry no steps, so only jobListOf, for a
  // source that reads no step, ever returns one, and none is carried.
  const listsMemo = new Map();
  const carriedHit = (run) => {
    const carried = run.status === "completed" && Number.isSafeInteger(run.run_attempt) ? carriedJobs.get(jobsKey(run.id, run.run_attempt)) : undefined;
    return carried !== undefined && carried.updated_at === run.updated_at;
  };
  const jobListOf = (run) => (jobsMemo.has(run.id) || carriedHit(run) || !listsMemo.has(run.id) ? jobsOf(run) : listsMemo.get(run.id));
  const warmLists = async (runs) => {
    const todo = runs.filter((r) => r.run_attempt === 1 && typeof r.node_id === "string" && !jobsMemo.has(r.id) && !listsMemo.has(r.id) && !carriedHit(r));
    const nodes = await readNodes(graphql, RUN_CHECK_RUNS, todo.map((r) => r.node_id));
    todo.forEach((run, i) => {
      const jobs = restJobs(nodes[i], run);
      if (jobs) listsMemo.set(run.id, jobs);
    });
  };
  const warmAnnotations = async (jobs) => {
    const todo = [...new Map(jobs.filter((j) => typeof j?.node_id === "string" && Number.isSafeInteger(j.id) && !annotationsMemo.has(j.id)).map((j) => [j.id, j])).values()];
    const nodes = await readNodes(graphql, CHECK_RUN_ANNOTATIONS, todo.map((j) => j.node_id));
    todo.forEach((job, i) => {
      const annotations = restAnnotations(nodes[i], job);
      if (annotations) annotationsMemo.set(job.id, annotations);
    });
  };
  // Reads `runs`' jobs in the order the source's loop does, stopping as it
  // would once `limit` jobs are picked, then the picked jobs' annotations in
  // batches. The loop reads jobs through the returned function, so a read that
  // failed here fails the loop at the same run, and is not made twice.
  const prefetch = async (runs, read, pick, limit = Number.POSITIVE_INFINITY) => {
    const got = new Map();
    const picked = [];
    let failed = null;
    for (const run of runs) {
      if (picked.length >= limit) break;
      try {
        const jobs = await read(run);
        got.set(run.id, jobs);
        picked.push(...pick(jobs, run));
      } catch (error) {
        failed = { id: run.id, error };
        break;
      }
    }
    await warmAnnotations(picked);
    return async (run) => {
      if (failed?.id === run.id) throw failed.error;
      return got.has(run.id) ? got.get(run.id) : read(run);
    };
  };
  const ownHead = (run) => run.head_repository?.full_name === repo;
  const trustedPrMerge = (run) => TRUSTED_EVENTS.has(run.event) && run.head_branch === "main" && ownHead(run);
  const failedJobs = (jobs) => jobs.filter((j) => ["failure", "timed_out"].includes(j.conclusion));
  const levelAndMessage = (a) => ({ level: a.annotation_level, message: a.message });
  const budgetReading = (a) => (a.title === "api-budget" ? parseBudget(a.message) : null);
  const created = `${iso(new Date(windowStart.getTime() - RUN_LOOKBACK_HOURS * 3600_000))}..${iso(now)}`;
  const completedInWindow = (run) => {
    const at = Date.parse(run.updated_at);
    return at >= windowStart.getTime() && at <= now.getTime();
  };
  const data = { now, windowStart, gaps };
  const source = async (name, read) => {
    try {
      await read();
    } catch (error) {
      gaps.push(`${name}: ${error.message}`);
    }
  };

  // pr-merge's runs on main, any status, listed once for the sources that
  // read them: post-merge-dispatch keeps its report while the run's merge
  // jobs still run, so the report source needs runs in progress too; the
  // budget source keeps completed ones only.
  let prMergeList = null;
  const prMergeRuns = async () =>
    (prMergeList ??= (await get(`/repos/${repo}/actions/workflows/pr-merge.yml/runs?branch=main&created=${created}&per_page=50`))
      .workflow_runs);

  await source("pr-merge api budget", async () => {
    const runs = await prMergeRuns();
    data.budgetReadings = [];
    const read = runs.filter((r) => r.status === "completed" && trustedPrMerge(r) && completedInWindow(r)).slice(0, LIMITS.prMergeRuns);
    await warmLists(read);
    const jobs = await prefetch(read, jobListOf, (js) => [mergeJob(js)].filter(Boolean));
    for (const run of read) {
      const merge = mergeJob(await jobs(run));
      if (!merge) continue;
      for (const a of await annotationsOf(merge.id)) {
        const reading = budgetReading(a);
        if (reading) data.budgetReadings.push({ ...reading, runId: run.id, url: run.html_url });
      }
    }
    if (ownRate) data.budgetReadings.push({ phase: "now", name: "github-token", ...ownRate, runId: null, url: null });
  });

  // The lanes App's own REST quota, which this job's GITHUB_TOKEN cannot
  // read: request-lane-token's `mint lanes-app` api-budget notice, from any
  // run of this repository's own head that completed in the window on an
  // event that runs the default branch's workflow code. Only a job whose
  // mint step succeeded is read, and a trusted pr-merge run's merge job is
  // left to the source above.
  const defaultBranchCode = (r) => DEFAULT_BRANCH_EVENTS.has(r.event) || (MAIN_ONLY_EVENTS.has(r.event) && r.head_branch === "main");
  await source("lane api budget", async () => {
    data.budgetReadings ??= [];
    const runs = (await get(`/repos/${repo}/actions/runs?status=completed&created=${created}&per_page=100`)).workflow_runs;
    const lanes = runs.filter((r) => defaultBranchCode(r) && !SKIP_FAILED_PATHS.has(r.path) && ownHead(r) && completedInWindow(r));
    let read = 0;
    const mintedOf = (jobs, run) => {
      const alreadyRead = (job) => run.path === PR_MERGE_PATH && trustedPrMerge(run) && job === mergeJob(jobs);
      return jobs.filter((j) => !alreadyRead(j) && (j.steps ?? []).some((s) => s.name === MINT_STEP && s.conclusion === "success"));
    };
    const jobs = await prefetch(lanes.slice(0, LIMITS.laneRuns), jobsOf, mintedOf, LIMITS.laneMintJobs);
    for (const run of lanes.slice(0, LIMITS.laneRuns)) {
      if (read >= LIMITS.laneMintJobs) return;
      const minted = mintedOf(await jobs(run), run);
      for (const job of minted) {
        if (read >= LIMITS.laneMintJobs) return;
        read += 1;
        for (const a of await annotationsOf(job.id)) {
          const reading = budgetReading(a);
          if (reading?.phase === "mint" && reading.name === "lanes-app") data.budgetReadings.push({ ...reading, runId: run.id, url: run.html_url });
        }
      }
    }
  });

  if (ownRate) {
    await source("Actions jobs in use", async () => {
      const runs = (await get(`/repos/${repo}/actions/runs?status=in_progress&per_page=100`)).workflow_runs;
      let inProgress = 0;
      await warmLists(runs.slice(0, LIMITS.inProgressRuns));
      for (const run of runs.slice(0, LIMITS.inProgressRuns)) {
        inProgress += (await jobListOf(run)).filter((j) => j.status === "in_progress").length;
      }
      data.jobsInUse = {
        inProgress,
        sampledRuns: Math.min(runs.length, LIMITS.inProgressRuns),
        truncated: runs.length > LIMITS.inProgressRuns,
      };
    });
  }

  // Fork and pull-request runs are dropped only after the read, so the read
  // pages: a flood of them on one page must not hide a failed run of this
  // repository's own. A run that fails mid-read shifts the pages, so one run
  // can come back on two of them; it is kept once.
  await source("failed runs", async () => {
    const kept = new Map();
    let unread = false;
    for (let page = 1; page <= LIMITS.failedRunPages && kept.size < LIMITS.failedRuns; page += 1) {
      const runs = (await get(`/repos/${repo}/actions/runs?status=failure&created=${created}&per_page=100&page=${page}`)).workflow_runs;
      for (const r of runs) {
        if (!SKIP_FAILED_EVENTS.has(r.event) && !SKIP_FAILED_PATHS.has(r.path) && ownHead(r) && completedInWindow(r)) kept.set(r.id, r);
      }
      unread = runs.length === 100;
      if (!unread) break;
    }
    data.failedRuns = [];
    const read = [...kept.values()].slice(0, LIMITS.failedRuns);
    await warmLists(read);
    const jobs = await prefetch(read, jobListOf, (js) => failedJobs(js).slice(0, LIMITS.failedJobsPerRun));
    for (const run of read) {
      const annotations = [];
      for (const job of failedJobs(await jobs(run)).slice(0, LIMITS.failedJobsPerRun)) {
        for (const a of await annotationsOf(job.id)) annotations.push(levelAndMessage(a));
      }
      data.failedRuns.push({ id: run.id, url: run.html_url, name: run.name, event: run.event, annotations });
    }
    if (unread && kept.size < LIMITS.failedRuns) {
      gaps.push(`failed runs: over ${LIMITS.failedRunPages * 100} failed runs in the window; the rest were not read`);
    }
  });

  // Signal 14's own read: main's failed scheduled work-unblock runs in the
  // window and their publish-lane-level job. A failure annotation names a
  // variable check result; a variable step that failed with none (a timeout)
  // is kept as a failed step. More runs than the cap is a gap, so the signal
  // reads unread rather than clear. A run that hit its timeout concludes
  // timed_out, so both conclusions are listed.
  await source("lane variable runs", async () => {
    const listed = [];
    for (const status of ["failure", "timed_out"]) {
      const page = await get(`/repos/${repo}/actions/workflows/work-unblock.yml/runs?event=schedule&branch=main&status=${status}&created=${created}&per_page=${LIMITS.laneVariableRuns + 1}`);
      listed.push(...page.workflow_runs.filter((r) => r.conclusion === status));
    }
    const runs = listed.filter((r) => r.path === WORK_UNBLOCK_PATH && r.event === "schedule" && r.head_branch === "main" && ownHead(r) && completedInWindow(r));
    if (listed.length > LIMITS.laneVariableRuns) {
      throw new Error(`over ${LIMITS.laneVariableRuns} failed scheduled work-unblock runs; the rest were not read`);
    }
    data.laneVariableRuns = [];
    const publishJob = (jobs) => failedJobs(jobs).find((j) => PUBLISH_LANE_LEVEL_NAMES.has(j.name));
    const jobs = await prefetch(runs, jobsOf, (js) => [publishJob(js)].filter(Boolean));
    for (const run of runs) {
      const job = publishJob(await jobs(run));
      if (!job) continue;
      const failedSteps = (job.steps ?? []).filter((s) => VARIABLE_STEPS.has(s.name) && s.conclusion && !["success", "skipped"].includes(s.conclusion)).map((s) => `${s.name}: ${s.conclusion}`);
      const annotations = (await annotationsOf(job.id)).map(levelAndMessage);
      data.laneVariableRuns.push({ id: run.id, url: run.html_url, name: run.name, event: run.event, annotations, failedSteps });
    }
  });

  await source("main full run", async () => {
    const runs = (
      await get(`/repos/${repo}/actions/workflows/pr-require-checks.yml/runs?branch=main&status=completed&created=<=${iso(now)}&per_page=20`)
    ).workflow_runs;
    const run = runs.find(
      (r) => ["workflow_dispatch", "schedule"].includes(r.event) && !["cancelled", "skipped"].includes(r.conclusion),
    );
    data.mainRun = null;
    if (!run) return;
    const jobs = [];
    if (["failure", "timed_out"].includes(run.conclusion)) {
      const read = await prefetch([run], jobsOf, (js) => failedJobs(js).slice(0, LIMITS.mainFailedJobs));
      for (const job of failedJobs(await read(run)).slice(0, LIMITS.mainFailedJobs)) {
        jobs.push({ name: job.name, conclusion: job.conclusion, annotations: (await annotationsOf(job.id)).map(levelAndMessage) });
      }
    }
    data.mainRun = {
      id: run.id,
      url: run.html_url,
      sha: run.head_sha,
      event: run.event,
      conclusion: run.conclusion,
      createdAt: run.created_at,
      failedJobs: jobs,
    };
  });

  await source("merge-queue ejections", async () => {
    const since = new Date(now.getTime() - 24 * 3600_000);
    const runs = (
      await get(`/repos/${repo}/actions/runs?event=merge_group&status=failure&created=${iso(since)}..${iso(now)}&per_page=50`)
    ).workflow_runs;
    // One merge group can fail in more than one workflow; it is one ejection.
    const groups = new Map();
    for (const run of runs) if (!groups.has(run.head_branch)) groups.set(run.head_branch, run);
    data.mergeGroupFailures = [];
    for (const [branch, run] of groups) {
      const detailed = data.mergeGroupFailures.length < LIMITS.mergeGroupRuns;
      const steps = [];
      if (detailed) {
        for (const job of failedJobs(await jobsOf(run))) {
          const failed = (job.steps ?? []).filter((s) => s.conclusion === "failure").map((s) => `${job.name} / ${s.name}`);
          steps.push(...(failed.length > 0 ? failed : [job.name]));
        }
      }
      data.mergeGroupFailures.push({
        id: run.id,
        url: run.html_url,
        pr: Number(QUEUE_BRANCH.exec(branch)?.[1]) || null,
        workflow: run.name,
        createdAt: run.created_at,
        failedSteps: steps,
      });
    }
  });

  // The newest sweep that listed, and the held sweeps above it, newest first:
  // a held summary carries no verdicts, so it never stands in for the sweep
  // signals 5 and 8 read. A trusted run that kept no summary neither counts
  // nor resets. Calls: one artifact list, one run read per artifact and one
  // download per trusted summary, stopping at the sweep that listed (3 while
  // the listing reads). None within the cap, or one older than
  // SWEEP_MAX_AGE_MINUTES, leaves no sweep and is a gap for signals 5 and 8,
  // under its own name: their issues neither clear nor file from stale data,
  // while signals 3 and 12 still fire.
  await source("pr-merge sweep", async () => {
    const artifacts = (await get(`/repos/${repo}/actions/artifacts?name=pr-merge-summary&per_page=100`)).artifacts;
    const candidates = artifacts
      // A fork's branch can also be named main; its artifacts must not fill the cap before the trust check.
      .filter(
        (a) =>
          !a.expired &&
          Date.parse(a.created_at) <= now.getTime() &&
          a.workflow_run?.head_branch === "main" &&
          a.workflow_run?.head_repository_id === a.workflow_run?.repository_id,
      )
      .slice(0, LIMITS.sweepArtifacts);
    data.sweep = null;
    data.heldSweeps = [];
    for (const a of candidates) {
      const run = await get(`/repos/${repo}/actions/runs/${a.workflow_run.id}`);
      if (run.path !== PR_MERGE_PATH || !trustedPrMerge(run)) continue;
      const s = await readArtifact(a.id);
      const runId = String(s.run_id);
      if (!["number", "string"].includes(typeof s.run_id) || !RUN_ID.test(runId) || runId !== String(a.workflow_run.id)) {
        throw new Error(`artifact ${a.id} names a run_id that is not its own run's id`);
      }
      const url = `https://github.com/${repo}/actions/runs/${runId}`;
      if (s.listing_held === true) {
        data.heldSweeps.push({ runId: Number(runId), url, reason: s.listing_held_reason ?? null, createdAt: a.created_at });
        continue;
      }
      data.sweep = {
        runId: Number(runId),
        url,
        event: s.event,
        live: s.live,
        startedAt: s.started_at ?? a.created_at,
        candidates: s.candidates,
        refusalCounts: s.refusal_counts ?? {},
        results: Array.isArray(s.results) ? s.results : [],
      };
      if (now.getTime() - Date.parse(data.sweep.startedAt) > SWEEP_MAX_AGE_MINUTES * 60_000) {
        data.sweep = null;
        gaps.push(`pr-merge listed sweep: the newest is over ${SWEEP_MAX_AGE_MINUTES} minutes old`);
      }
      return;
    }
    if (data.heldSweeps.length > 0) gaps.push(`pr-merge listed sweep: none in the ${LIMITS.sweepArtifacts} newest summaries`);
  });

  // The report post-merge-dispatch keeps per sweep (pr-merge-post-merge-report:
  // the post-merge check's exit code and JSON), from trusted pr-merge runs
  // only, a run still in progress included, newest first, stopping at the first that is not exit 3 or at
  // POST_MERGE_UNREADABLE_SWEEPS. A run that kept no report (not live, a rate
  // stop) neither counts nor resets. No report within SWEEP_MAX_AGE_MINUTES
  // is a gap, so an open issue is not cleared without a readable sweep. Calls:
  // the shared run list, one artifact list, and one download per report read
  // (one when the newest is readable, at most POST_MERGE_UNREADABLE_SWEEPS).
  await source("post-merge reports", async () => {
    const trusted = new Set((await prMergeRuns()).filter(trustedPrMerge).map((r) => r.id));
    const artifacts = (await get(`/repos/${repo}/actions/artifacts?name=pr-merge-post-merge-report&per_page=${LIMITS.postMergeArtifacts}`)).artifacts ?? [];
    const kept = artifacts.filter((a) => !a.expired && Date.parse(a.created_at) <= now.getTime() && trusted.has(a.workflow_run?.id));
    data.postMergeReports = [];
    if (kept.length === 0 || now.getTime() - Date.parse(kept[0].created_at) > SWEEP_MAX_AGE_MINUTES * 60_000) {
      throw new Error(`no report from a trusted pr-merge run in the last ${SWEEP_MAX_AGE_MINUTES} minutes`);
    }
    for (const a of kept.slice(0, POST_MERGE_UNREADABLE_SWEEPS)) {
      const files = await readArtifact(a.id, ["post-merge-code", "post-merge.json"]);
      const code = String(files["post-merge-code"] ?? "").trim();
      let reason = null;
      try {
        reason = JSON.parse(files["post-merge.json"])?.reason ?? null;
      } catch {
        // No JSON: the code alone decides.
      }
      data.postMergeReports.push({
        runId: a.workflow_run.id,
        url: `https://github.com/${repo}/actions/runs/${a.workflow_run.id}`,
        code,
        reason: reason === null ? null : String(reason),
        createdAt: a.created_at,
      });
      if (code !== "3") break;
    }
  });

  await source("lane merges", async () => {
    const pulls = await get(`/repos/${repo}/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100`);
    const merged = pulls
      .filter((p) => p.merged_at && p.user?.login === agentIdentity && Date.parse(p.merged_at) <= now.getTime())
      .map((p) => p.merged_at)
      .sort();
    data.laneMerges = { lastMergedAt: merged.at(-1) ?? null };
  });

  // work-resolve-issue's outcome markers, from the lanes App only: anyone who
  // can comment can paste one. `since` filters on update time, so the
  // creation time is checked here.
  await source("lane stops", async () => {
    data.laneStops = [];
    let unread = false;
    for (let page = 1; page <= LIMITS.commentPages; page += 1) {
      const batch = await get(
        `/repos/${repo}/issues/comments?since=${iso(windowStart)}&sort=created&direction=desc&per_page=100&page=${page}`,
      );
      // Newest first: once a page reaches back before the window, nothing older matters.
      unread = batch.length === 100 && !batch.some((c) => Date.parse(c.created_at) < windowStart.getTime());
      for (const c of batch) {
        const at = Date.parse(c.created_at);
        if (c.user?.login !== agentIdentity || at < windowStart.getTime() || at > now.getTime()) continue;
        const marker = parseOutcomeMarker(c.body);
        if (!marker) continue;
        const issue = Number(/\/issues\/(\d+)$/.exec(c.issue_url ?? "")?.[1]) || null;
        data.laneStops.push({ id: c.id, outcome: marker.outcome, issue, url: c.html_url, createdAt: c.created_at });
      }
      if (!unread) break;
    }
    if (unread) gaps.push(`lane stops: over ${LIMITS.commentPages * 100} comments in the window; the oldest were not read`);
  });

  // Held runs of the HOLD_LANES: green runs (and red ones, for a lane whose
  // statuses list failure) of this repository's head on the default branch's
  // code that completed in the window, whose hold job succeeded with a hold
  // notice or warning (signals.mjs parseHold), one entry per run,
  // added to the carried ones still inside the rule's window. A run already
  // carried is not read again, nor counted against LIMITS.holdRuns, and nor is
  // a run carried as read with no hold while its completion time is the one
  // carried: a new attempt is read again. Those runs are carried while they
  // completed inside the run list's lookback from this window, the oldest the
  // next run can list. The carry also records the span it was read over,
  // which ends at the last run read
  // when a lane had more than the cap. It stays unbroken when the last run
  // read through a time inside the run list's lookback: runs that completed
  // since then are read, so a late cron loses none. Otherwise (no carry, a
  // stale one, a failed read) it starts again at this window. An unread rule
  // is a gap that leaves signal 13 unread. A lane over the cap, or a span
  // shorter than the rule's window, is a partly-read gap: holds read in part
  // of the window are a floor on the whole window's, so a lane at the
  // threshold still files or keeps its issue, but the issue never clears on
  // such a read. The carried runs still go on to the next run.
  const heldRuns = new Map();
  const scannedRuns = new Map();
  const listedRuns = new Map();
  let heldFrom = null;
  let heldThrough = null;
  if (holds) {
    const { carried } = holds;
    for (const h of carried?.runs ?? []) heldRuns.set(`${h.lane}:${h.runId}`, h);
    for (const s of carried?.scanned ?? []) scannedRuns.set(`${s.lane}:${s.runId}`, s);
    const through = Date.parse(carried?.through);
    const unbroken = carried?.from && through >= windowStart.getTime() - RUN_LOOKBACK_HOURS * 3600_000 && through <= now.getTime();
    heldFrom = unbroken ? carried.from : iso(windowStart);
    const readFrom = unbroken ? Math.min(through, windowStart.getTime()) : windowStart.getTime();
    const completedSince = (run) => {
      const at = Date.parse(run.updated_at);
      return at >= readFrom && at <= now.getTime();
    };
    await source("lane holds", async () => {
      // The span is read through now unless a lane has more unread runs than
      // the cap: then only its oldest are read, and the span stops at the last
      // of them, so the next run reads the rest and this one reports a gap.
      let readThrough = now.getTime();
      const cut = [];
      for (const { lane, workflow, jobs: ids, names, holdRuns: cap = LIMITS.holdRuns, listPages = LIMITS.holdListPages, holdStep, statuses = ["success"] } of HOLD_LANES) {
        // A job by its name, or by its id on a run from before the job rename.
        const jobs = [...names, ...ids];
        // By id: a run that starts between two page reads shifts one onto the next page.
        const runs = new Map();
        for (const status of statuses) {
          const listed = new Set();
          for (let page = 1; ; page += 1) {
            const listing = await get(`/repos/${repo}/actions/workflows/${workflow}/runs?status=${status}&created=${created}&per_page=100${page > 1 ? `&page=${page}` : ""}`);
            for (const r of listing.workflow_runs) {
              runs.set(r.id, r);
              listed.add(r.id);
            }
            if (listing.workflow_runs.length < 100 || listed.size >= (listing.total_count ?? 0)) break;
            if (page >= listPages) throw new Error(`over ${listPages * 100} ${status === "success" ? "green" : "red"} runs of ${lane} listed; the oldest were not read`);
          }
        }
        listedRuns.set(lane, new Map([...runs].filter(([, r]) => defaultBranchCode(r) && ownHead(r))));
        const unread = [...runs.values()]
          .filter((r) => defaultBranchCode(r) && ownHead(r) && completedSince(r) && !heldRuns.has(`${lane}:${r.id}`) && scannedRuns.get(`${lane}:${r.id}`)?.at !== r.updated_at)
          .sort((a, b) => Date.parse(a.updated_at) - Date.parse(b.updated_at));
        if (unread.length > cap) {
          readThrough = Math.min(readThrough, Date.parse(unread[cap - 1].updated_at));
          cut.push(`${lane} (cap ${cap})`);
        }
        // Each lane's jobs are listed through GraphQL, which carries no steps,
        // so every green hold job's annotations are read in its batch. A list
        // read through REST has steps: with holdStep, only a job whose listing
        // shows that step succeeded printed a hold, so only its annotations
        // are read one call each; a job listed with no steps is read too.
        // With holdStep, a run whose GraphQL-listed hold job the annotation
        // batch did not answer is listed again through REST, one call per run,
        // so its annotations are read only where that step ran.
        const printed = (j) =>
          holdStep === undefined || !Array.isArray(j.steps) || j.steps.length === 0 || j.steps.some((s) => s?.name === holdStep && s.conclusion === "success");
        const holding = (listed) => listed.filter((j) => j.conclusion === "success" && holdJob(jobs, j.name) && printed(j));
        const toRead = unread.slice(0, cap);
        await warmLists(toRead);
        const jobsFor = await prefetch(toRead, jobListOf, holding);
        for (const run of toRead) {
          const key = `${lane}:${run.id}`;
          const found = [];
          let listed = await jobsFor(run);
          if (holdStep !== undefined && holding(listed).some((j) => !Array.isArray(j.steps) && !annotationsMemo.has(j.id))) listed = await jobsOf(run);
          for (const job of holding(listed)) {
            for (const a of await annotationsOf(job.id)) {
              const hold = parseHold(a.title, a.message, a.annotation_level);
              if (hold) found.push(hold);
            }
          }
          if (found.length === 0) {
            scannedRuns.set(key, { lane, runId: run.id, at: run.updated_at });
            continue;
          }
          scannedRuns.delete(key);
          heldRuns.set(key, {
            lane,
            runId: run.id,
            url: run.html_url,
            item: found.find((h) => h.item)?.item ?? null,
            reason: [...new Set(found.map((h) => h.reason))].sort().join("; "),
            at: run.updated_at,
          });
        }
      }
      heldThrough = iso(new Date(readThrough));
      if (holds.rule instanceof Error) throw holds.rule;
      const since = now.getTime() - holds.rule.windowHours * 3600_000;
      for (const [key, h] of heldRuns) {
        const at = Date.parse(h.at);
        if (at < since || at > now.getTime()) heldRuns.delete(key);
      }
      data.holdRule = holds.rule;
      const partly = [];
      if (cut.length > 0) partly.push(`over the cap of unread green runs of ${cut.join(", ")}; held runs read only through ${heldThrough}`);
      if (Date.parse(heldFrom) > since) partly.push(`held runs read only since ${heldFrom}, short of the ${holds.rule.windowHours}-hour window`);
      if (partly.length > 0) gaps.push(`lane holds partly read: ${partly.join("; ")}`);
    });

    // The lane-hold-<lane> artifact each hold job keeps for a day when it held
    // (lib/lane-hold-marker.mjs): one list call per lane, newest 100. A marker
    // counts only for a run the lane's listing above holds, so it passes the
    // same trust and status checks, and only for a run the scan did not find
    // held, whose read reason stands. It reaches the runs the scan's cap
    // leaves unread. Past 100 markers the newest stand as a floor: that many
    // is over any threshold. A lane with no listing is the scan's gap.
    if (!(holds.rule instanceof Error)) {
      await source("lane hold markers", async () => {
        const since = now.getTime() - holds.rule.windowHours * 3600_000;
        for (const { lane } of HOLD_LANES) {
          const runs = listedRuns.get(lane);
          if (!runs) continue;
          const { artifacts = [] } = await get(`/repos/${repo}/actions/artifacts?name=lane-hold-${lane}&per_page=100`);
          for (const a of artifacts) {
            const run = !a.expired && runs.get(a.workflow_run?.id);
            const at = Date.parse(run?.updated_at);
            if (!run || at < since || at > now.getTime() || heldRuns.has(`${lane}:${run.id}`)) continue;
            scannedRuns.delete(`${lane}:${run.id}`);
            heldRuns.set(`${lane}:${run.id}`, { lane, runId: run.id, url: run.html_url, item: null, reason: "hold marker", at: run.updated_at });
          }
        }
      });
    }
  }
  data.laneHolds = [...heldRuns.values()].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, LIMITS.holdsKept);
  const listedSince = windowStart.getTime() - RUN_LOOKBACK_HOURS * 3600_000;
  const scanned = [...scannedRuns.values()].filter((s) => {
    const at = Date.parse(s.at);
    return at >= listedSince && at <= now.getTime();
  });
  // Marker-only holds are carried like the rest: the run listing reaches back
  // only about 7 h, so the carry is what keeps a marked hold in the 24-hour
  // count. Its reason stays "hold marker"; the scan reads forward from its
  // last read and does not come back for it.
  data.heldCarry = { runs: data.laneHolds, from: heldThrough ? heldFrom : null, through: heldThrough, scanned };

  // Open pull requests whose head carries a stop the pr-unblock lane routed to
  // a failing status (its lane-stopped comment, by the lanes App, names the
  // PR's current head) with no attempt of that activity started on the head
  // since the comment's last edit, and no stop-resolved skip ending it:
  // its per-head retries are spent. Any PR, not only
  // the lanes App's: fix-ci adopts owners'. The status itself needs
  // statuses: read, which this job's token lacks, so the comment and the
  // activity's check runs stand for it.
  await source("stalled stops", async () => {
    data.stalledStops = [];
    const cutoff = now.getTime() - STALLED_HOURS * 3600_000;
    let checks = 0;
    const listed = await queryRepo(
      graphql,
      repo,
      `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { pullRequests(states: OPEN, baseRefName: "main", first: ${LIMITS.stalledPulls}, orderBy: { field: UPDATED_AT, direction: DESC }) { totalCount nodes { number headRefOid comments(last: 100) { ${COMMENT_PAGE} } } } } }`,
    );
    if (!listed.pullRequests) throw new Error("GraphQL: no open pull request list");
    const total = listed.pullRequests.totalCount ?? 0;
    if (total > LIMITS.stalledPulls) {
      gaps.push(`stalled stops: ${total} open pull requests, only the ${LIMITS.stalledPulls} most recently updated read`);
    }
    const pulls = (listed.pullRequests.nodes ?? []).map((node) => ({
      number: node.number,
      head: node.headRefOid,
      comments: (node.comments?.nodes ?? []).map(restComment),
      older: node.comments?.pageInfo?.hasPreviousPage ? node.comments.pageInfo.startCursor : null,
    }));
    // A PR's own markers on its current head: a lane-stopped comment naming it,
    // or a cleared label for it. An older head's marker says nothing of this
    // head's stop, which can sit in an older comment edited in place.
    const marks = (pull) =>
      pull.comments.some((c) => {
        if (c.user?.login !== agentIdentity) return false;
        const body = String(c.body ?? "").replaceAll("\r\n", "\n");
        const first = body.split("\n")[0];
        return (LANE_STOPPED.test(first) && STOP_FIELD("Head").exec(body)?.[1] === pull.head) || CLEARED.exec(first)?.[2] === pull.head;
      });
    for (let round = 0; round < LIMITS.stalledCommentRounds; round += 1) {
      const deeper = pulls.filter((pull) => pull.older !== null && !marks(pull));
      if (deeper.length === 0) break;
      const older = await queryRepo(
        graphql,
        repo,
        batchQuery(deeper.map((pull) => `pullRequest(number: ${pull.number}) { comments(last: 100, before: ${JSON.stringify(pull.older)}) { ${COMMENT_PAGE} } }`)),
      );
      for (const [i, pull] of deeper.entries()) {
        const page = older[`a${i}`]?.comments;
        pull.comments = [...(page?.nodes ?? []).map(restComment), ...pull.comments];
        pull.older = page?.pageInfo?.hasPreviousPage ? page.pageInfo.startCursor : null;
      }
    }
    for (const pull of pulls) {
      const { head, comments } = pull;
      // Each stop on this head: the newest lane-stopped comment per activity,
      // or a cleared label whose reason is now routed to a failing status.
      const stops = new Map();
      for (const c of comments) {
        if (c.user?.login !== agentIdentity) continue;
        const lines = String(c.body ?? "").split("\n").map((line) => line.replace(/\r$/, ""));
        const body = lines.join("\n");
        const activity = LANE_STOPPED.exec(lines[0])?.[1];
        if (activity) {
          if (STOP_FIELD("Head").exec(body)?.[1] === head) {
            stops.set(activity, { activity, reason: STOP_FIELD("Reason").exec(body)?.[1] ?? "unknown", stoppedAt: c.updated_at ?? c.created_at, url: c.html_url });
          }
          continue;
        }
        const cleared = CLEARED.exec(lines[0]);
        if (cleared && cleared[2] === head) {
          for (const reason of cleared[1].split(",")) {
            const of = escalationActivity(reason);
            // feedback-not-landed clears only once its cause is gone (no
            // unresolved lane thread on a moved head), so no stop stands.
            if (escalationRoute(reason) === "fail" && reason !== "feedback-not-landed" && !stops.has(of)) {
              stops.set(of, { activity: of, reason, stoppedAt: c.created_at, url: c.html_url });
            }
          }
        }
      }
      if (pull.older !== null && !marks(pull)) {
        gaps.push(`stalled stops: #${pull.number} has over ${comments.length} comments and none names a stop on its head; older ones not read`);
      }
      for (const stop of stops.values()) {
        if (!(Date.parse(stop.stoppedAt) < cutoff)) continue;
        if (checks >= LIMITS.stalledChecks) {
          gaps.push(`stalled stops: over ${LIMITS.stalledChecks} candidate stops; #${pull.number} and later not judged`);
          return;
        }
        checks += 1;
        const runs = (await get(`/repos/${repo}/commits/${head}/check-runs?check_name=${encodeURIComponent(`pr-unblock / ${stop.activity}`)}&filter=all&per_page=100`)).check_runs ?? [];
        const since = runs.filter((run) => Date.parse(run.started_at) > Date.parse(stop.stoppedAt));
        if (since.some((run) => attempted(run) || run.output?.title === STOP_RESOLVED)) continue;
        data.stalledStops.push({ pr: pull.number, head, ...stop });
      }
    }
  });

  await source("audits", async () => {
    data.audits = [];
    for (const workflow of AUDIT_WORKFLOWS) {
      const [run] = (
        await get(`/repos/${repo}/actions/workflows/${workflow}.yml/runs?event=schedule&status=completed&created=<=${iso(now)}&per_page=1`)
      ).workflow_runs;
      if (!run) continue;
      const failed = run.conclusion === "failure" ? failedJobs(await jobsOf(run)).map((j) => j.name) : [];
      data.audits.push({
        workflow,
        run: { id: run.id, url: run.html_url, conclusion: run.conclusion, createdAt: run.created_at, failedJobs: failed },
      });
    }
  });

  await source("githubstatus.com", async () => {
    const summary = await getStatus("https://www.githubstatus.com/api/v2/summary.json");
    const recent = await getStatus("https://www.githubstatus.com/api/v2/incidents.json");
    const incidents = new Map();
    for (const i of [...(summary.incidents ?? []), ...(recent.incidents ?? [])]) {
      if (incidents.has(i.id) || Date.parse(i.created_at) > now.getTime()) continue;
      incidents.set(i.id, { ...i, components: (i.components ?? []).map((c) => c.name) });
    }
    data.status = {
      components: (summary.components ?? []).map((c) => ({ name: c.name, status: c.status })),
      incidents: [...incidents.values()],
    };
  });

  data.jobsCarry = [...keptJobs.values()];
  return data;
}

// Issues the lane filed: github-actions[bot]'s, any state and any age, newest
// first. The lane writes nothing while evidence is unchanged, so an update-time
// cutoff would drop a quiet open or muted key, and a page cap would drop the
// oldest. Paging stops at a short page; the call budget bounds it, and spending
// it throws before any write. The caller keeps those carrying the marker.
export async function listFiled({ get, repo }) {
  const out = [];
  for (let page = 1; ; page += 1) {
    const batch = await get(
      `/repos/${repo}/issues?creator=${encodeURIComponent("github-actions[bot]")}&state=all&sort=created&direction=desc&per_page=100&page=${page}`,
    );
    out.push(...batch.filter((i) => !i.pull_request));
    if (batch.length < 100) break;
  }
  return out;
}
