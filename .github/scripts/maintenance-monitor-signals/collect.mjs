// The monitoring lane's reads: every source the signals need, through the
// job's own GITHUB_TOKEN and githubstatus.com, into one data object. A source
// that fails to read is recorded in `gaps` and the others still run. Every
// list is bounded, and `get` spends the run's call budget.
import { parseBudget } from "./signals.mjs";

export const LIMITS = {
  prMergeRuns: 12,
  inProgressRuns: 30,
  failedRuns: 12,
  failedJobsPerRun: 3,
  mainFailedJobs: 5,
  mergeGroupRuns: 10,
  issuePages: 5,
};
export const AUDIT_WORKFLOWS = ["maintenance-audit-test-selection", "maintenance-check-upstream-drift"];
// Pull-request and merge-group runs hold no lane token, and a merge-group
// failure is counted as an ejection instead.
const SKIP_FAILED_EVENTS = new Set(["pull_request", "merge_group"]);
const QUEUE_BRANCH = /^gh-readonly-queue\/[^/]+\/pr-(\d+)-[0-9a-f]+$/;
const iso = (date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");

export async function collect({ get, getStatus, readArtifact, repo, now, windowStart, agentIdentity, ownRate = null }) {
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
  const failedJobs = (jobs) => jobs.filter((j) => ["failure", "timed_out"].includes(j.conclusion));
  const window = `${iso(windowStart)}..${iso(now)}`;
  const data = { now, windowStart, gaps };
  const source = async (name, read) => {
    try {
      await read();
    } catch (error) {
      gaps.push(`${name}: ${error.message}`);
    }
  };

  await source("pr-merge api budget", async () => {
    const runs = (await get(`/repos/${repo}/actions/workflows/pr-merge.yml/runs?status=completed&created=${window}&per_page=20`))
      .workflow_runs;
    data.budgetReadings = [];
    for (const run of runs.slice(0, LIMITS.prMergeRuns)) {
      const merge = (await jobsOf(run.id)).find((j) => j.name === "merge");
      if (!merge) continue;
      for (const a of await annotationsOf(merge.id)) {
        const reading = a.title === "api-budget" ? parseBudget(a.message) : null;
        if (reading) data.budgetReadings.push({ ...reading, runId: run.id, url: run.html_url });
      }
    }
    if (ownRate) data.budgetReadings.push({ phase: "now", name: "github-token", ...ownRate, runId: null, url: null });
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

  await source("failed runs", async () => {
    const runs = (await get(`/repos/${repo}/actions/runs?status=failure&created=${window}&per_page=50`)).workflow_runs;
    data.failedRuns = [];
    for (const run of runs.filter((r) => !SKIP_FAILED_EVENTS.has(r.event)).slice(0, LIMITS.failedRuns)) {
      const annotations = [];
      for (const job of failedJobs(await jobsOf(run.id)).slice(0, LIMITS.failedJobsPerRun)) {
        for (const a of await annotationsOf(job.id)) annotations.push({ level: a.annotation_level, message: a.message });
      }
      data.failedRuns.push({ id: run.id, url: run.html_url, name: run.name, event: run.event, annotations });
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
    data.mainRun = { id: run.id, url: run.html_url, sha: run.head_sha, event: run.event, conclusion: run.conclusion, failedJobs: jobs };
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

  await source("pr-merge sweep", async () => {
    const artifacts = (await get(`/repos/${repo}/actions/artifacts?name=pr-merge-summary&per_page=100`)).artifacts;
    const newest = artifacts.find((a) => !a.expired && Date.parse(a.created_at) <= now.getTime());
    data.sweep = null;
    if (!newest) return;
    const s = await readArtifact(newest.id);
    data.sweep = {
      runId: s.run_id,
      url: `https://github.com/${repo}/actions/runs/${s.run_id}`,
      event: s.event,
      live: s.live,
      startedAt: s.started_at ?? newest.created_at,
      candidates: s.candidates,
      refusalCounts: s.refusal_counts ?? {},
      results: Array.isArray(s.results) ? s.results : [],
    };
  });

  await source("lane merges", async () => {
    const pulls = await get(`/repos/${repo}/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100`);
    const merged = pulls
      .filter((p) => p.merged_at && p.user?.login === agentIdentity && Date.parse(p.merged_at) <= now.getTime())
      .map((p) => p.merged_at)
      .sort();
    data.laneMerges = { lastMergedAt: merged.at(-1) ?? null };
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

// Issues the lane filed: github-actions[bot]'s, any state, updated within 30
// days. The caller keeps those carrying the marker.
export async function listFiled({ get, repo, now }) {
  const since = iso(new Date(now.getTime() - 30 * 24 * 3600_000));
  const out = [];
  for (let page = 1; page <= LIMITS.issuePages; page += 1) {
    const batch = await get(
      `/repos/${repo}/issues?creator=${encodeURIComponent("github-actions[bot]")}&state=all&since=${since}&per_page=100&page=${page}`,
    );
    out.push(...batch.filter((i) => !i.pull_request));
    if (batch.length < 100) break;
  }
  return out;
}
