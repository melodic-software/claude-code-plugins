import { parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";
import { escalationActivity, escalationRoute, STOP_RESOLVED } from "../pr-unblock/escalation-routes.mjs";
import { HOLD_LANES, holdJob, parseBudget, parseHold, POST_MERGE_UNREADABLE_SWEEPS, STALLED_HOURS, SWEEP_MAX_AGE_MINUTES } from "./signals.mjs";
import { stepsKnown } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { CHECK_RUN_ANNOTATIONS, isObject, jobsKey, readNodes, restAnnotations, restJobs, RUN_CHECK_RUNS, slimJob } from "../lib/run-jobs.mjs";

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
  laneVariableRuns: 10,
  failedJobsPerRun: 3,
  mainFailedJobs: 5,
  mergeGroupList: 100,
  mergeGroupRuns: 10,
  mergeQueuePulls: 50,
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
  // first. Only work-resolve-issue uses this default. The other lanes,
  // including pr-refine, set their own caps (signals.mjs HOLD_LANES holdRuns).
  // Each status costs up to holdListPages run list pages (pr-verify and
  // pr-merge set 5, pr-review-main sets 4, and pr-refine lists green and red
  // separately), then each run's jobs and the annotations of each green
  // hold job are read. Every lane's jobs are read in one GraphQL query per
  // 25 runs, and its annotations in one per 25 jobs. A run has one green
  // hold job (pr-verify's one of three), with up to 4 for pr-refine, about 3
  // for pr-review-main (its trigger and two review legs), and up to 2 for
  // pr-merge. In lane order, that is at most 3 + 3 + 6 + 3 + 5 + 4 + 5 list
  // pages, 1 + 1 + 1 + 2 + 4 + 3 + 4 job list queries and
  // 1 + 1 + 2 + 2 + 4 + 9 + 7 annotation queries (71 calls, 42 of them
  // GraphQL), plus one lane-hold marker list per lane (7). A re-run, or a
  // node GraphQL does not answer, is read through REST, one call a jobs or
  // annotation read; a REST list has steps, so pr-verify and pr-review-main
  // (holdStep) read only a job whose `Note the hold` ran, and a run of theirs
  // whose GraphQL-listed hold job the annotation batch did not answer is
  // listed again through REST first. With GraphQL refused, or answering the
  // lists but not the annotations, those two lanes spend at most 7 + 150
  // list calls and one annotation read per held job, not 290 for every green
  // hold job; the other lanes'
  // 158 job lists and about 274 annotation reads put the source past
  // CALL_BUDGET at the caps either way. Past the cap, the span stops at the
  // last run read and the window is a gap. pr-refine's cap of 12:
  // https://github.com/melodic-software/claude-code-plugins/issues/16656
  holdRuns: 6,
  // Run list pages of 100 per hold lane, unless the lane sets its own
  // (HOLD_LANES listPages): intake-triage listed up to 151 green runs over the
  // 7-hour created span in the 7 days to 2026-11-05. A lane with more is a
  // gap, since its oldest-created runs go unlisted.
  holdListPages: 3,
  holdsKept: 300,
};
const LANE_STOPPED = /^<!-- pr-unblock:lane-stopped activity=([a-z]+(?:-[a-z]+)*) -->$/;
const STOP_FIELD = (name) => new RegExp(`^- ${name}: \`([^\`]+)\``, "m");
const CLEARED = /^<!-- pr-pipeline needs-human-cleared reason=([a-z,-]+) head=([0-9a-f]{40}) -->$/;
export const batchQuery = (fields) =>
  `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${fields.map((field, i) => `a${i}: ${field}`).join(" ")} } }`;
async function queryRepo(graphql, repo, query) {
  const [owner, name] = repo.split("/");
  const result = await graphql(query, { owner, name });
  if (result?.errors?.length) throw new Error(`GraphQL: ${result.errors.map((e) => e.message).join("; ")}`);
  return result?.data?.repository ?? {};
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
const attempted = (run) => !(run.conclusion === "neutral" && String(run.output?.title ?? "").startsWith("Skipped:"));
export const AUDIT_WORKFLOWS = ["maintenance-audit-test-selection", "maintenance-file-upstream-drift-issues"];
const SKIP_FAILED_EVENTS = new Set(["pull_request", "merge_group"]);
const SKIP_FAILED_PATHS = new Set([".github/workflows/pr-require-checks.yml", ".github/workflows/pr-test-platforms.yml"]);
const QUEUE_BRANCH = /^gh-readonly-queue\/[^/]+\/pr-(\d+)-[0-9a-f]+$/;
export const QUEUE_HOLD_STEPS = new Set(["Fail a queued pull request a hold stops, before the lanes", "Fail a lanes App pull request on kill switch, hold path, verifier or veto"]);
export const KILL_SWITCH = /^#\d+: the lanes kill switch is on \(/;
const QUEUE_ITEMS = 100;
const QUEUE_PULLS_BATCH = 25;
const QUEUE_FIELDS =
  "pageInfo { hasPreviousPage } nodes { __typename ... on AddedToMergeQueueEvent { createdAt } ... on RemovedFromMergeQueueEvent { createdAt reason } ... on LabeledEvent { createdAt label { name } } }";

export function queueRemovals(pr, nodes, since) {
  const out = [];
  let enqueuedAt = null;
  let labels = [];
  for (const node of nodes) {
    if (node?.__typename === "AddedToMergeQueueEvent") {
      enqueuedAt = node.createdAt;
      labels = [];
    } else if (node?.__typename === "LabeledEvent") {
      if (enqueuedAt !== null && typeof node.label?.name === "string") labels.push(node.label.name);
    } else if (node?.__typename === "RemovedFromMergeQueueEvent") {
      if (node.reason === "failed_checks" && Date.parse(node.createdAt) >= since.getTime()) out.push({ pr, at: node.createdAt, enqueuedAt, labels });
      enqueuedAt = null;
      labels = [];
    }
  }
  return out;
}
const WORK_UNBLOCK_PATH = ".github/workflows/work-unblock.yml";
export const PUBLISH_LANE_LEVEL_JOB = "publish-lane-level";
const PUBLISH_LANE_LEVEL_NAMES = new Set(["Publish Lane Level", PUBLISH_LANE_LEVEL_JOB]);
export const VARIABLE_STEPS = new Set(["List the repository variables before the publish", "Check no other repository variable changed"]);
// Only main's own scheduled or dispatched pr-merge runs are trusted: a PR,
// fork or branch run can upload an artifact or annotation of the same name.
const TRUSTED_EVENTS = new Set(["schedule", "workflow_dispatch"]);
const PR_MERGE_PATH = ".github/workflows/pr-merge.yml";
const MERGE_JOB = "Merge";
const MERGE_JOB_BEFORE_RENAME = "merge";
const mergeJob = (jobs) => jobs.find((j) => j.name === MERGE_JOB) ?? jobs.find((j) => j.name === MERGE_JOB_BEFORE_RENAME);
const MINT_STEP = "Request the lane token";
// Events whose run takes its workflow code from the default branch; a push
// or a dispatch counts only on main. A pull_request or review event runs a
// branch's code, which could write a notice of the same shape.
const DEFAULT_BRANCH_EVENTS = new Set(["schedule", "workflow_run", "pull_request_target", "issues", "issue_comment"]);
const MAIN_ONLY_EVENTS = new Set(["push", "workflow_dispatch"]);
const RUN_ID = /^[0-9]+$/;
const RUN_LOOKBACK_HOURS = 6;
const iso = (date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");

export const JOBS_ARTIFACT = "monitor-signals-jobs";
export const JOBS_FILE = "jobs.json";
export const JOBS_VERSION = 2;
const isTimeOrNull = (value) => value === null || (typeof value === "string" && !Number.isNaN(Date.parse(value)));

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
    const listing = await get(`/repos/${repo}/actions/runs?event=merge_group&status=failure&created=${iso(since)}..${iso(now)}&per_page=${LIMITS.mergeGroupList}`);
    const runs = listing.workflow_runs;
    if (listing.total_count > runs.length) {
      gaps.push(`merge-queue ejections: ${listing.total_count} failed merge-group runs in 24 hours, only the newest ${LIMITS.mergeGroupList} listed`);
    }
    const groups = new Map();
    for (const run of runs) if (!groups.has(run.head_branch)) groups.set(run.head_branch, run);
    const detailed = [...groups.values()].slice(0, LIMITS.mergeGroupRuns);
    const jobs = await prefetch(detailed, jobsOf, (js) => failedJobs(js).filter((j) => (j.steps ?? []).some((s) => s.conclusion === "failure" && QUEUE_HOLD_STEPS.has(s.name))));
    data.mergeGroupFailures = [];
    for (const [branch, run] of groups) {
      const steps = [];
      let killSwitch = false;
      if (detailed.includes(run)) {
        for (const job of failedJobs(await jobs(run))) {
          const failed = (job.steps ?? []).filter((s) => s.conclusion === "failure");
          steps.push(...(failed.length > 0 ? failed.map((s) => `${job.name} / ${s.name}`) : [job.name]));
          if (failed.some((s) => QUEUE_HOLD_STEPS.has(s.name))) {
            killSwitch ||= (await annotationsOf(job.id)).some((a) => a.annotation_level === "failure" && KILL_SWITCH.test(String(a.message)));
          }
        }
      }
      data.mergeGroupFailures.push({
        id: run.id,
        url: run.html_url,
        pr: Number(QUEUE_BRANCH.exec(branch)?.[1]) || null,
        workflow: run.name,
        createdAt: run.created_at,
        failedSteps: steps,
        killSwitch,
      });
    }
    const pulls = [...new Set(data.mergeGroupFailures.map((f) => f.pr).filter(Boolean))];
    if (pulls.length > LIMITS.mergeQueuePulls) {
      throw new Error(`${pulls.length} pull requests with a failed merge group, over the ${LIMITS.mergeQueuePulls} read`);
    }
    const from = iso(new Date(since.getTime() - RUN_LOOKBACK_HOURS * 3600_000));
    data.mergeQueueRemovals = [];
    for (let i = 0; i < pulls.length; i += QUEUE_PULLS_BATCH) {
      const batch = pulls.slice(i, i + QUEUE_PULLS_BATCH);
      const answer = await queryRepo(graphql, repo, batchQuery(batch.map((n) => `pullRequest(number: ${n}) { timelineItems(since: "${from}", last: ${QUEUE_ITEMS}, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT, LABELED_EVENT]) { ${QUEUE_FIELDS} } }`)));
      batch.forEach((pr, j) => {
        const items = answer[`a${j}`]?.timelineItems;
        const nodes = items?.nodes;
        const cut = items?.pageInfo?.hasPreviousPage;
        if (!Array.isArray(nodes) || typeof cut !== "boolean") throw new Error(`#${pr}'s merge-queue timeline did not read`);
        if (cut) gaps.push(`merge-queue ejections: #${pr}'s merge-queue timeline holds more than ${QUEUE_ITEMS} items in the window; the older ones were not read`);
        data.mergeQueueRemovals.push(...queueRemovals(pr, nodes, since));
      });
    }
  });

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
      let readThrough = now.getTime();
      const cut = [];
      for (const { lane, workflow, jobs: ids, names, earlier = [], holdRuns: cap = LIMITS.holdRuns, listPages = LIMITS.holdListPages, holdStep, statuses = ["success"] } of HOLD_LANES) {
        const jobs = [...names, ...ids, ...earlier];
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
