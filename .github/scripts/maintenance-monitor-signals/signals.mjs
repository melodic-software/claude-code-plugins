// The monitoring lane's signals: each detector reads the collected data and
// returns findings, one per dedup key. No network. A finding is
// {key, signal, title, area, summary, facts, fingerprint, observedAt}: the key
// names the issue, the fingerprint changes only when the evidence does, so an
// unchanged recurrence updates nothing. observedAt, when set, is when the
// evidence was produced: a key closed before then is a regression. Every text that came from a run, a PR or the
// status page is made inert here (one line, no backticks) before it reaches
// an issue.
import { createHash } from "node:crypto";

export const CEILING = 0.9;
export const ACTIONS_JOB_LIMIT = 60;
export const EJECTIONS_PER_DAY = 2;
export const HELD_HOURS = 24;
export const STALL_HOURS = 3;
// pr-unblock-dispatch.yml runs every 30 minutes (cron 9,39), and the feedback
// sweep runs off each of those ticks, so a stop the lane will retry gets a new
// attempt within one tick; four ticks with none mean the per-head retries are
// spent (or a dispatcher refused).
export const STALLED_HOURS = 2;
export const SWEEP_MAX_AGE_MINUTES = 70;
// The owner's threshold (#9170): this many pr-merge sweeps in a row whose
// post-merge check exited 3 (unreadable), about an hour at the 15-minute cron.
export const POST_MERGE_UNREADABLE_SWEEPS = 4;
// This many scheduled or hand-started pr-merge sweeps in a row whose listing
// held, about an hour at the same cron.
export const LISTING_HELD_SWEEPS = 4;
const MAX_FACTS = 25;

export const inert = (text, max = 300) =>
  Array.from(String(text ?? "").replace(/[\r\n`]+/g, " ").replace(/\s+/g, " ").trim())
    .slice(0, max)
    .join("");

const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex").slice(0, 16);
const slug = (text) =>
  String(text)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60) || "unnamed";
const day = (date) => date.toISOString().slice(0, 10);
const pct = (used, limit) => `${((used / limit) * 100).toFixed(1)}%`;

function finding({ key, signal, title, area, summary, facts, evidence, observedAt = null }) {
  return {
    observedAt,
    key,
    signal,
    title: inert(title, 120),
    area,
    summary: inert(summary, 500),
    facts: facts.slice(0, MAX_FACTS).map((line) => inert(line)),
    fingerprint: hash(evidence),
  };
}

// pr-merge's api-budget notices, from .github/actions/log-api-budget: at
// start `<phase> <name> core remaining=R used=U limit=L reset=<ISO> ...`, at
// end `token=<name> workflow=... limit=L remaining=R used=U ... resource=core ...`
// (a graphql or search reading is not the REST quota).
export function parseBudget(message) {
  const text = String(message);
  const m = /^([a-z]+) ([a-z][a-z0-9-]*) core remaining=(\d+) used=(\d+) limit=(\d+) /.exec(text);
  if (m) return { phase: m[1], name: m[2], remaining: Number(m[3]), used: Number(m[4]), limit: Number(m[5]) };
  const e = /^token=([a-z][a-z0-9-]*) .* limit=(\d+) remaining=(\d+) used=(\d+) reset=\S+ resource=core /.exec(text);
  if (e) return { phase: "end", name: e[1], remaining: Number(e[3]), used: Number(e[4]), limit: Number(e[2]) };
  return null;
}

const CEILINGS = [
  { names: ["lanes-app", "lane"], key: "ceiling:lanes-app-rest", label: "the lanes App REST quota" },
  { names: ["github-token"], key: "ceiling:github-token", label: "the GITHUB_TOKEN REST quota" },
];

export function ceilingFindings({ now, budgetReadings = [], jobsInUse = null }) {
  const out = [];
  for (const { names, key, label } of CEILINGS) {
    const readings = budgetReadings.filter((r) => names.includes(r.name) && r.limit > 0);
    if (readings.length === 0) continue;
    const peak = readings.reduce((a, b) => (b.used / b.limit > a.used / a.limit ? b : a));
    if (peak.used / peak.limit <= CEILING) continue;
    out.push(
      finding({
        key,
        signal: "2 ceiling",
        title: `Ceiling: ${label} passed 90% in the last hour`,
        area: "GitHub Support (API and Actions limits)",
        summary: `Peak reading ${peak.used} of ${peak.limit} used (${pct(peak.used, peak.limit)}), ${peak.remaining} remaining, over ${readings.length} readings in the last hour.`,
        facts: readings
          .filter((r) => r.used / r.limit > CEILING)
          .map((r) => `${r.phase} ${r.name}: used ${r.used} of ${r.limit} (${pct(r.used, r.limit)}) ${r.url ?? "this run"}`),
        evidence: [key, day(now)],
      }),
    );
  }
  if (jobsInUse && jobsInUse.inProgress / ACTIONS_JOB_LIMIT > CEILING) {
    out.push(
      finding({
        key: "ceiling:actions-jobs",
        signal: "2 ceiling",
        title: "Ceiling: Actions jobs in use passed 90% of 60",
        area: "GitHub Support (API and Actions limits)",
        summary: `${jobsInUse.inProgress} jobs in progress against ${ACTIONS_JOB_LIMIT} (${pct(jobsInUse.inProgress, ACTIONS_JOB_LIMIT)}), sampled across ${jobsInUse.sampledRuns} in-progress runs of this repository${jobsInUse.truncated ? " (sample capped, so a lower bound)" : ""}.`,
        facts: [`sampled at ${now.toISOString()}`],
        evidence: ["ceiling:actions-jobs", day(now)],
      }),
    );
  }
  return out;
}

// Broker refusals from request-lane-token's annotations. workflow-modified is
// left out: pr-merge re-fires those runs on its schedule.
const RATE_LIMITED = /github-rate-limited|rate limit|\b429\b/i;
const BROKER_DENY = /^lane-(?:token|check)-denied: the broker answered (\d{3}) with reason ([a-z]+(?:-[a-z]+)*)/;
const BROKER_UNREACHABLE = /^broker-unreachable:/;
const EXPECTED_REASONS = new Set(["workflow-modified"]);

export function throttleFindings({ windowStart, failedRuns = [], budgetReadings = [], heldSweeps = [] }) {
  const groups = new Map();
  const add = (key, runId, line) => {
    const group = groups.get(key) ?? { runs: new Set(), lines: [] };
    group.runs.add(runId);
    group.lines.push(line);
    groups.set(key, group);
  };
  for (const run of failedRuns) {
    for (const { level, message } of run.annotations ?? []) {
      if (level !== "failure") continue;
      const text = String(message);
      const deny = BROKER_DENY.exec(text);
      let key = null;
      if (RATE_LIMITED.test(text)) key = "throttle:rate-limited";
      else if (deny && !EXPECTED_REASONS.has(deny[2])) key = `broker-deny:${deny[1]}-${deny[2]}`;
      else if (BROKER_UNREACHABLE.test(text)) key = "broker-deny:unreachable";
      if (key) add(key, run.id, `${run.name} ${run.url}: ${text}`);
    }
  }
  for (const r of budgetReadings) {
    if (r.limit > 0 && r.remaining === 0) {
      add("throttle:rate-limited", r.runId ?? "this run", `${r.phase} ${r.name}: 0 of ${r.limit} remaining ${r.url ?? "this run"}`);
    }
  }
  // A listing a rate limit held ends its run green, so no annotation names it.
  // Only a hold still unbroken at the monitoring run is seen: collect's walk
  // stops at the first listed summary.
  for (const s of heldSweeps) {
    if (String(s.reason).startsWith("rate limited") && Date.parse(s.createdAt) >= windowStart.getTime()) {
      add("throttle:rate-limited", s.runId, `pr-merge listing held ${s.url}: ${s.reason}`);
    }
  }
  return [...groups].map(([key, { runs, lines }]) =>
    finding({
      key,
      signal: "3 throttling",
      title:
        key === "throttle:rate-limited"
          ? "Throttling: GitHub rate limits hit in the last hour"
          : `Broker deny: ${key.slice("broker-deny:".length)} in the last hour`,
      area: "GitHub Support (lanes token broker and rate limits)",
      summary: `${lines.length} occurrences across ${runs.size} runs in the last hour.`,
      facts: lines,
      evidence: [key, [...runs].map(String).sort()],
    }),
  );
}

// GitHub's own runner messages name the flake class; anything else is not
// known.
function flakeClass(job) {
  if (job.conclusion === "timed_out") return "timeout";
  const text = (job.annotations ?? []).map((a) => a.message).join(" ");
  if (/lost communication with the server|runner has received a shutdown signal/i.test(text)) return "runner lost";
  return "not known";
}

export function mainRedFindings({ mainRun = null }) {
  if (!mainRun || !["failure", "timed_out"].includes(mainRun.conclusion)) return [];
  const out = [];
  for (const job of mainRun.failedJobs ?? []) {
    const failures = (job.annotations ?? []).filter((a) => a.level === "failure");
    if (failures.length === 0) continue;
    const name = String(job.name).replace(/ \(.*\)$/, "");
    const key = `main-red:${slug(name)}`;
    out.push(
      finding({
        key,
        signal: "1 main red",
        title: `Main red: ${name} fails on main`,
        area: "CI (pr-require-checks on main)",
        summary: `${job.name} failed in the newest full run on main (${mainRun.event}) at ${String(mainRun.sha).slice(0, 12)}: ${mainRun.url}`,
        facts: [`flake class: ${flakeClass(job)}`, ...failures.map((a) => `failure: ${a.message}`)],
        evidence: [key, failures.map((a) => String(a.message).replace(/\d+/g, "N")).sort()],
        observedAt: mainRun.createdAt ?? null,
      }),
    );
  }
  return out;
}

export function ejectionFindings({ mergeGroupFailures = [] }) {
  if (mergeGroupFailures.length <= EJECTIONS_PER_DAY) return [];
  return [
    finding({
      key: "merge-queue-ejections",
      signal: "4 merge-queue ejections",
      title: `Merge queue: ${mergeGroupFailures.length} ejections in the last 24 hours`,
      area: "Merge lane (pr-merge and the merge queue)",
      summary: `${mergeGroupFailures.length} merge-group runs failed in the last 24 hours, over the ${EJECTIONS_PER_DAY} a day this lane allows.`,
      facts: mergeGroupFailures.map(
        (r) => `#${r.pr ?? "?"} ${r.workflow} ${r.createdAt}: ${(r.failedSteps ?? []).join("; ") || "no failed step listed"} ${r.url}`,
      ),
      // The newest group only: an old group leaving the 24-hour window is not new evidence.
      evidence: ["merge-queue-ejections", Math.max(...mergeGroupFailures.map((r) => Number(r.id)))],
    }),
  ];
}

// pr-merge's "Blocked for over 24 hours" list, from its newest sweep.
export function heldFindings({ now, sweep = null }) {
  if (!sweep) return [];
  const cutoff = now.getTime() - HELD_HOURS * 3600_000;
  const held = (sweep.results ?? [])
    .filter((r) => !r.enqueued && !r.merged && Date.parse(r.updatedAt) < cutoff)
    .sort((a, b) => a.pr - b.pr);
  if (held.length === 0) return [];
  return [
    finding({
      key: "held-over-24h",
      signal: "5 held PRs",
      title: `Held PRs: ${held.length} blocked and untouched for over 24 hours`,
      area: "Merge lane (pr-merge)",
      summary: `pr-merge's newest sweep (${sweep.url}) lists ${held.length} PRs blocked and not updated for over 24 hours; each needs a person.`,
      facts: held.map((r) => `#${r.pr} since ${r.updatedAt}: ${r.reason ?? "not ready"}`),
      evidence: ["held-over-24h", held.map((r) => r.pr)],
    }),
  ];
}

export function auditFindings({ audits = [] }) {
  return audits
    .filter(({ run }) => run?.conclusion === "failure")
    .map(({ workflow, run }) =>
      finding({
        key: `audit:${slug(workflow)}`,
        signal: "6 report-only audit",
        title: `Audit findings: ${workflow} reported findings`,
        area: "Maintenance audits",
        summary: `The newest scheduled run of ${workflow} (${run.createdAt}) failed, which this audit does when it has findings: ${run.url}`,
        facts: (run.failedJobs ?? []).map((name) => `failed job: ${name}`),
        evidence: [`audit:${workflow}`, String(run.id)],
      }),
    );
}

// githubstatus.com: an incident naming Actions that is open or began in the
// window, or Actions not operational with no such incident.
export function platformFindings({ windowStart, status = null }) {
  if (!status) return [];
  const actions = (status.components ?? []).find((c) => c.name === "Actions");
  const incidents = (status.incidents ?? []).filter(
    (i) =>
      (i.components ?? []).includes("Actions") &&
      (i.status !== "resolved" || Date.parse(i.created_at) >= windowStart.getTime()),
  );
  const out = incidents.map((i) =>
    finding({
      key: `platform:${slug(i.id)}`,
      signal: "7 platform incident",
      title: `GitHub incident: ${i.name}`,
      area: "GitHub Support (platform incident)",
      summary: `githubstatus.com incident ${i.status} since ${i.created_at}: ${i.shortlink}`,
      facts: [`components: ${(i.components ?? []).join(", ")}`, `Actions component: ${actions?.status ?? "unknown"}`],
      evidence: [`platform:${i.id}`, i.status],
    }),
  );
  if (out.length === 0 && actions && actions.status !== "operational") {
    out.push(
      finding({
        key: "platform:actions",
        signal: "7 platform incident",
        title: "GitHub Actions is not operational",
        area: "GitHub Support (platform incident)",
        summary: `githubstatus.com reports Actions as ${actions.status} with no incident naming it.`,
        facts: [],
        evidence: ["platform:actions", actions.status],
      }),
    );
  }
  return out;
}

export function throughputFindings({ now, sweep = null, laneMerges = null }) {
  if (!sweep || !laneMerges || sweep.live !== true || !(sweep.candidates > 0)) return [];
  if (now.getTime() - Date.parse(sweep.startedAt) > SWEEP_MAX_AGE_MINUTES * 60_000) return [];
  const last = laneMerges.lastMergedAt;
  if (last && now.getTime() - Date.parse(last) < STALL_HOURS * 3600_000) return [];
  return [
    finding({
      key: "throughput-zero",
      signal: "8 throughput",
      title: `Throughput: no lane merge for ${STALL_HOURS} hours or more`,
      area: "Merge lane (pr-merge)",
      summary: `No lane PR merged since ${last ?? "before the listed window"} while pr-merge's newest sweep counts ${sweep.candidates} candidates: ${sweep.url}`,
      facts: Object.entries(sweep.refusalCounts ?? {}).map(([reason, n]) => `refused ${n}: ${reason}`),
      evidence: ["throughput-zero", last],
    }),
  ];
}

// work-resolve-issue's stops that need a person to know: out of funding, the
// usage limit, the turn cap, or a stop whose retries are spent (`failed`,
// which adds no label, so this is where it shows).
const LANE_STOPS = new Set(["funding", "limited", "turn-cap", "failed"]);

export function laneStopFindings({ laneStops = [] }) {
  const groups = new Map();
  for (const stop of laneStops) {
    if (!LANE_STOPS.has(stop.outcome)) continue;
    groups.set(stop.outcome, [...(groups.get(stop.outcome) ?? []), stop]);
  }
  return [...groups].map(([outcome, stops]) =>
    finding({
      key: `lane-stop:${outcome}`,
      signal: "9 lane stop",
      title: `Lane stop: ${stops.length} issue-lane runs stopped with ${outcome} in the last hour`,
      area: "Issue lane (work-resolve-issue)",
      summary: `work-resolve-issue left ${stops.length} outcome=${outcome} markers in the last hour.`,
      facts: stops.map((s) => `#${s.issue ?? "?"} ${s.createdAt}: ${s.url}`),
      // The newest stop only: a stop seen again in the window's overlap with the
      // previous run keeps the fingerprint, so a completed issue is not reopened.
      evidence: [`lane-stop:${outcome}`, Math.max(...stops.map((s) => Number(s.id)))],
    }),
  );
}

// Pull requests a pr-unblock stop left red with no retry left on their head
// (collect.mjs, "stalled stops"): no person was asked, so this tells one.
export function stalledFindings({ stalledStops = [] }) {
  if (stalledStops.length === 0) return [];
  const stops = [...stalledStops].sort((a, b) => a.pr - b.pr || a.activity.localeCompare(b.activity));
  return [
    finding({
      key: "stalled-lane-stop",
      signal: "10 stalled lane stop",
      title: `Stalled: ${stops.length} pull request stops the PR fix lane left red for over ${STALLED_HOURS} hours`,
      area: "PR fix lane (pr-unblock)",
      summary: `${stops.length} pull requests carry a failing pr-unblock status the lane can no longer retry on their head; each needs a new commit or a look at its stop comment.`,
      facts: stops.map((s) => `#${s.pr} ${s.activity} ${s.reason} since ${s.stoppedAt}: ${s.url}`),
      evidence: ["stalled-lane-stop", stops.map((s) => [s.pr, s.head, s.activity, s.reason])],
    }),
  ];
}

// pr-merge's post-merge check could not read lane merges (exit 3) in each of
// its newest POST_MERGE_UNREADABLE_SWEEPS sweeps, so merges hold with only a
// warning. It only notifies; a readable sweep clears it. The fingerprint is
// the newest reason with its counts masked, so a cause that holds is written
// once.
export function postMergeUnreadableFindings({ postMergeReports = [] }) {
  const streak = postMergeReports.slice(0, POST_MERGE_UNREADABLE_SWEEPS);
  if (streak.length < POST_MERGE_UNREADABLE_SWEEPS || streak.some((r) => r.code !== "3")) return [];
  const [newest] = streak;
  const reason = (r) => r.reason ?? "no reason recorded";
  return [
    finding({
      key: "post-merge-unreadable",
      signal: "11 post-merge unreadable",
      title: `Post-merge check: unreadable in the last ${POST_MERGE_UNREADABLE_SWEEPS} pr-merge sweeps`,
      area: "Merge lane (pr-merge post-merge check)",
      summary: `pr-merge's post-merge check exited 3 (unreadable) in each of its last ${POST_MERGE_UNREADABLE_SWEEPS} sweeps, so lane merges hold until a sweep reads again. Newest ${newest.url}: ${reason(newest)}`,
      facts: streak.map((r) => `${r.createdAt} ${r.url}: ${reason(r)}`),
      evidence: ["post-merge-unreadable", reason(newest).replace(/\d+/g, "N")],
      observedAt: newest.createdAt,
    }),
  ];
}

// pr-merge's open pull requests were unknown in each of its newest
// LISTING_HELD_SWEEPS sweeps, so the job gates nothing while its runs end green
// with only a notice. It only notifies; a sweep that lists clears it. The
// fingerprint is the newest reason with its counts masked, so a cause that
// holds is written once.
export function listingHeldFindings({ heldSweeps = [] }) {
  if (heldSweeps.length < LISTING_HELD_SWEEPS) return [];
  const streak = heldSweeps.slice(0, LISTING_HELD_SWEEPS);
  const [newest] = streak;
  const reason = (s) => s.reason ?? "no reason recorded";
  return [
    finding({
      key: "listing-held",
      signal: "12 listing held",
      title: `Merge lane: listing held in the last ${LISTING_HELD_SWEEPS} pr-merge sweeps`,
      area: "Merge lane (pr-merge listing)",
      summary: `pr-merge could not list the open pull requests in each of its last ${LISTING_HELD_SWEEPS} sweeps, so its merge job gated nothing and its runs stayed green. Newest ${newest.url}: ${reason(newest)}`,
      facts: streak.map((s) => `${s.createdAt} ${s.url}: ${reason(s)}`),
      evidence: ["listing-held", reason(newest).replace(/\d+/g, "N")],
      observedAt: newest.createdAt,
    }),
  ];
}

const DETECTORS = [
  mainRedFindings,
  ceilingFindings,
  throttleFindings,
  ejectionFindings,
  heldFindings,
  auditFindings,
  platformFindings,
  throughputFindings,
  laneStopFindings,
  stalledFindings,
  postMergeUnreadableFindings,
  listingHeldFindings,
];

export function detect(data) {
  const byKey = new Map();
  for (const detector of DETECTORS) {
    for (const f of detector(data)) if (!byKey.has(f.key)) byKey.set(f.key, f);
  }
  return [...byKey.values()];
}
