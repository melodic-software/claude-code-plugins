// The monitoring lane's reads: every source the signals need, through the
// job's own GITHUB_TOKEN and githubstatus.com, into one data object. A source
// that fails to read is recorded in `gaps` and the others still run. Every
// list is bounded, and `get` spends the run's call budget.
import { parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";
import { escalationActivity, escalationRoute, STOP_RESOLVED } from "../pr-unblock/escalation-routes.mjs";
import { parseBudget, POST_MERGE_UNREADABLE_SWEEPS, STALLED_HOURS, SWEEP_MAX_AGE_MINUTES } from "./signals.mjs";

export const LIMITS = {
  prMergeRuns: 12,
  // Lane runs whose jobs the lanes App quota read lists, newest first, and the
  // jobs with a successful mint step whose annotations it reads, in all: at
  // most 1 + 10 + 10 calls. A sample, not every mint in the window.
  laneRuns: 10,
  laneMintJobs: 10,
  inProgressRuns: 30,
  failedRuns: 12,
  failedRunPages: 5,
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
// Only main's own scheduled or dispatched pr-merge runs are trusted: a PR,
// fork or branch run can upload an artifact or annotation of the same name.
const TRUSTED_EVENTS = new Set(["schedule", "workflow_dispatch"]);
const PR_MERGE_PATH = ".github/workflows/pr-merge.yml";
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

export async function collect({ get, graphql, getStatus, readArtifact, repo, now, windowStart, agentIdentity, ownRate = null }) {
  const gaps = [];
  const jobsMemo = new Map();
  const annotationsMemo = new Map();
  const jobsOf = async (runId) => {
    if (!jobsMemo.has(runId)) {
      jobsMemo.set(runId, (await get(`/repos/${repo}/actions/runs/${runId}/jobs?filter=latest&per_page=100`)).jobs ?? []);
    }
    return jobsMemo.get(runId);
  };
  const annotationsOf = async (jobId) => {
    if (!annotationsMemo.has(jobId)) {
      annotationsMemo.set(jobId, (await get(`/repos/${repo}/check-runs/${jobId}/annotations?per_page=100`)) ?? []);
    }
    return annotationsMemo.get(jobId);
  };
  const ownHead = (run) => run.head_repository?.full_name === repo;
  const trustedPrMerge = (run) => TRUSTED_EVENTS.has(run.event) && run.head_branch === "main" && ownHead(run);
  const failedJobs = (jobs) => jobs.filter((j) => ["failure", "timed_out"].includes(j.conclusion));
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
    for (const run of runs.filter((r) => r.status === "completed" && trustedPrMerge(r) && completedInWindow(r)).slice(0, LIMITS.prMergeRuns)) {
      const merge = (await jobsOf(run.id)).find((j) => j.name === "merge");
      if (!merge) continue;
      for (const a of await annotationsOf(merge.id)) {
        const reading = a.title === "api-budget" ? parseBudget(a.message) : null;
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
    for (const run of lanes.slice(0, LIMITS.laneRuns)) {
      if (read >= LIMITS.laneMintJobs) return;
      const alreadyRead = (job) => run.path === PR_MERGE_PATH && trustedPrMerge(run) && job.name === "merge";
      const minted = (await jobsOf(run.id)).filter(
        (j) => !alreadyRead(j) && (j.steps ?? []).some((s) => s.name === MINT_STEP && s.conclusion === "success"),
      );
      for (const job of minted) {
        if (read >= LIMITS.laneMintJobs) return;
        read += 1;
        for (const a of await annotationsOf(job.id)) {
          const reading = a.title === "api-budget" ? parseBudget(a.message) : null;
          if (reading?.phase === "mint" && reading.name === "lanes-app") data.budgetReadings.push({ ...reading, runId: run.id, url: run.html_url });
        }
      }
    }
  });

  if (ownRate) {
    await source("Actions jobs in use", async () => {
      const runs = (await get(`/repos/${repo}/actions/runs?status=in_progress&per_page=100`)).workflow_runs;
      let inProgress = 0;
      for (const run of runs.slice(0, LIMITS.inProgressRuns)) {
        inProgress += (await jobsOf(run.id)).filter((j) => j.status === "in_progress").length;
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
    for (const run of [...kept.values()].slice(0, LIMITS.failedRuns)) {
      const annotations = [];
      for (const job of failedJobs(await jobsOf(run.id)).slice(0, LIMITS.failedJobsPerRun)) {
        for (const a of await annotationsOf(job.id)) annotations.push({ level: a.annotation_level, message: a.message });
      }
      data.failedRuns.push({ id: run.id, url: run.html_url, name: run.name, event: run.event, annotations });
    }
    if (unread && kept.size < LIMITS.failedRuns) {
      gaps.push(`failed runs: over ${LIMITS.failedRunPages * 100} failed runs in the window; the rest were not read`);
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
      for (const job of failedJobs(await jobsOf(run.id)).slice(0, LIMITS.mainFailedJobs)) {
        const annotations = (await annotationsOf(job.id)).map((a) => ({ level: a.annotation_level, message: a.message }));
        jobs.push({ name: job.name, conclusion: job.conclusion, annotations });
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
        for (const job of failedJobs(await jobsOf(run.id))) {
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
    const pulls = (listed.pullRequests?.nodes ?? []).map((node) => ({
      number: node.number,
      head: { sha: node.headRefOid },
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
        return (LANE_STOPPED.test(first) && STOP_FIELD("Head").exec(body)?.[1] === pull.head.sha) || CLEARED.exec(first)?.[2] === pull.head.sha;
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
      const head = pull.head?.sha;
      const comments = pull.comments;
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
      const failed = run.conclusion === "failure" ? failedJobs(await jobsOf(run.id)).map((j) => j.name) : [];
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
