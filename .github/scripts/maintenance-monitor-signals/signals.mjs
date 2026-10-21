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
const SWEEP_MAX_AGE_MINUTES = 70;
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

// pr-merge's api-budget notice, from .github/actions/log-api-budget:
// `<phase> <name> core remaining=R used=U limit=L reset=<ISO> ...`.
export function parseBudget(message) {
  const m = /^([a-z]+) ([a-z][a-z0-9-]*) core remaining=(\d+) used=(\d+) limit=(\d+) /.exec(String(message));
  if (!m) return null;
  return { phase: m[1], name: m[2], remaining: Number(m[3]), used: Number(m[4]), limit: Number(m[5]) };
}

const CEILINGS = [
  { name: "lane", key: "ceiling:lanes-app-rest", label: "the lanes App REST quota" },
  { name: "github-token", key: "ceiling:github-token", label: "the GITHUB_TOKEN REST quota" },
];

export function ceilingFindings({ now, budgetReadings = [], jobsInUse = null }) {
  const out = [];
  for (const { name, key, label } of CEILINGS) {
    const readings = budgetReadings.filter((r) => r.name === name && r.limit > 0);
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

export function throttleFindings({ failedRuns = [], budgetReadings = [] }) {
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
// usage limit, or the turn cap.
const LANE_STOPS = new Set(["funding", "limited", "turn-cap"]);

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
      evidence: [`lane-stop:${outcome}`, stops.map((s) => Number(s.id)).sort((a, b) => a - b)],
    }),
  );
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
];

export function detect(data) {
  const byKey = new Map();
  for (const detector of DETECTORS) {
    for (const f of detector(data)) if (!byKey.has(f.key)) byKey.set(f.key, f);
  }
  return [...byKey.values()];
}
