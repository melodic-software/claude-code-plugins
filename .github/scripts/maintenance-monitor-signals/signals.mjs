import { createHash } from "node:crypto";

import { listedJob } from "../lib/lane-registry.mjs";
import { labelHolds } from "../pr-merge/merge-holds.mjs";

export const CEILING = 0.9;
export const ACTIONS_JOB_LIMIT = 60;
export const EJECTIONS_PER_DAY = 2;
export const HELD_HOURS = 24;
export const STALL_HOURS = 3;
export const STALLED_HOURS = 2;
export const SWEEP_MAX_AGE_MINUTES = 70;
export const POST_MERGE_UNREADABLE_SWEEPS = 4;
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
const share = (r) => r.used / r.limit;
const masked = (text) => text.replace(/\d+/g, "N");
const reasonOf = (r) => r.reason ?? "no reason recorded";

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
    const peak = readings.reduce((a, b) => (share(b) > share(a) ? b : a));
    if (share(peak) <= CEILING) continue;
    out.push(
      finding({
        key,
        signal: "2 ceiling",
        title: `Ceiling: ${label} passed 90% in the last hour`,
        area: "GitHub Support (API and Actions limits)",
        summary: `Peak reading ${peak.used} of ${peak.limit} used (${pct(peak.used, peak.limit)}), ${peak.remaining} remaining, over ${readings.length} readings in the last hour.`,
        facts: readings
          .filter((r) => share(r) > CEILING)
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
        evidence: [key, failures.map((a) => masked(String(a.message))).sort()],
        observedAt: mainRun.createdAt ?? null,
      }),
    );
  }
  return out;
}

const isHoldLabel = (name) => labelHolds([name], null, 0).length > 0;
const at = (iso) => Date.parse(iso);

export function ejectionFindings({ mergeQueueRemovals = [], mergeGroupFailures = [] }) {
  const judged = mergeQueueRemovals.map((r) => {
    const runs = mergeGroupFailures
      .filter((f) => f.pr === r.pr && at(f.createdAt) <= at(r.at) && (r.enqueuedAt === null || at(f.createdAt) >= at(r.enqueuedAt)))
      .sort((a, b) => at(b.createdAt) - at(a.createdAt));
    const label = (r.labels ?? []).find(isHoldLabel);
    const held = label ? `'${label}' added while queued` : r.enqueuedAt !== null && runs.some((f) => f.killSwitch) ? "the lanes kill switch failed its group" : null;
    return { ...r, run: runs[0] ?? null, held };
  });
  const counted = judged.filter((r) => !r.held).sort((a, b) => at(b.at) - at(a.at));
  if (counted.length <= EJECTIONS_PER_DAY) return [];
  const notCounted = judged.filter((r) => r.held);
  const [newest] = counted;
  return [
    finding({
      key: "merge-queue-ejections",
      signal: "4 merge-queue ejections",
      title: `Merge queue: ${counted.length} ejections in the last 24 hours`,
      area: "Merge lane (pr-merge and the merge queue)",
      summary: `${counted.length} merge-queue removals for failed checks in the last 24 hours, over the ${EJECTIONS_PER_DAY} a day this lane allows. ${mergeGroupFailures.length} merge groups failed; ${notCounted.length} removals a hold applied while queued caused are not counted.`,
      facts: [
        ...counted.map(({ pr, at: removedAt, run }) =>
          run
            ? `#${pr} removed ${removedAt}: ${(run.failedSteps ?? []).join("; ") || "no failed step listed"} ${run.url}`
            : `#${pr} removed ${removedAt}: no failed merge-group run read`,
        ),
        ...notCounted.map(({ pr, at: removedAt, held }) => `not counted: #${pr} removed ${removedAt}: ${held}`),
      ],
      evidence: ["merge-queue-ejections", newest.pr, newest.at],
    }),
  ];
}

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
        title: `Audit failed: the newest scheduled run of ${workflow} failed`,
        area: "Maintenance audits",
        summary: `The newest scheduled run of ${workflow} (${run.createdAt}) failed. A report-only audit fails when it has findings; the drift filer fails on a failed issue write, an unreachable upstream, or a check script that exited outside its exit contract, each after filing every issue, or its report job fails with nothing filed when a drift check could not finish. The run's annotations name the cause: ${run.url}`,
        facts: (run.failedJobs ?? []).map((name) => `failed job: ${name}`),
        evidence: [`audit:${workflow}`, String(run.id)],
      }),
    );
}

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

const LANE_STOPS = new Set(["funding", "limited", "turn-cap", "failed"]);

export function laneStopFindings({ laneStops = [] }) {
  const groups = new Map();
  for (const stop of laneStops) {
    if (!LANE_STOPS.has(stop.outcome)) continue;
    if (!groups.has(stop.outcome)) groups.set(stop.outcome, []);
    groups.get(stop.outcome).push(stop);
  }
  return [...groups].map(([outcome, stops]) =>
    finding({
      key: `lane-stop:${outcome}`,
      signal: "9 lane stop",
      title: `Lane stop: ${stops.length} issue-lane runs stopped with ${outcome} in the last hour`,
      area: "Issue lane (work-resolve-issue)",
      summary: `work-resolve-issue left ${stops.length} outcome=${outcome} markers in the last hour.`,
      facts: stops.map((s) => `#${s.issue ?? "?"} ${s.createdAt}: ${s.url}`),
      evidence: [`lane-stop:${outcome}`, Math.max(...stops.map((s) => Number(s.id)))],
    }),
  );
}

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

export function postMergeUnreadableFindings({ postMergeReports = [] }) {
  const streak = postMergeReports.slice(0, POST_MERGE_UNREADABLE_SWEEPS);
  if (streak.length < POST_MERGE_UNREADABLE_SWEEPS || streak.some((r) => r.code !== "3")) return [];
  const [newest] = streak;
  return [
    finding({
      key: "post-merge-unreadable",
      signal: "11 post-merge unreadable",
      title: `Post-merge check: unreadable in the last ${POST_MERGE_UNREADABLE_SWEEPS} pr-merge sweeps`,
      area: "Merge lane (pr-merge post-merge check)",
      summary: `pr-merge's post-merge check exited 3 (unreadable) in each of its last ${POST_MERGE_UNREADABLE_SWEEPS} sweeps, so lane merges hold until a sweep reads again. Newest ${newest.url}: ${reasonOf(newest)}`,
      facts: streak.map((r) => `${r.createdAt} ${r.url}: ${reasonOf(r)}`),
      evidence: ["post-merge-unreadable", masked(reasonOf(newest))],
      observedAt: newest.createdAt,
    }),
  ];
}

export function listingHeldFindings({ heldSweeps = [] }) {
  if (heldSweeps.length < LISTING_HELD_SWEEPS) return [];
  const streak = heldSweeps.slice(0, LISTING_HELD_SWEEPS);
  const [newest] = streak;
  return [
    finding({
      key: "listing-held",
      signal: "12 listing held",
      title: `Merge lane: listing held in the last ${LISTING_HELD_SWEEPS} pr-merge sweeps`,
      area: "Merge lane (pr-merge listing)",
      summary: `pr-merge could not list the open pull requests in each of its last ${LISTING_HELD_SWEEPS} sweeps, so its merge job gated nothing and its runs stayed green. Newest ${newest.url}: ${reasonOf(newest)}`,
      facts: streak.map((s) => `${s.createdAt} ${s.url}: ${reasonOf(s)}`),
      evidence: ["listing-held", masked(reasonOf(newest))],
      observedAt: newest.createdAt,
    }),
  ];
}

const LANE_VARIABLES = /^lane-variables-(?:changed|unread):/;

export function laneVariableFindings({ laneVariableRuns = [] }) {
  const lines = [];
  const runs = new Set();
  for (const run of laneVariableRuns) {
    const before = lines.length;
    for (const { level, message } of run.annotations ?? []) {
      if (level === "failure" && LANE_VARIABLES.test(String(message))) {
        lines.push(`${run.name} ${run.url}: ${message}`);
      }
    }
    if (lines.length === before) {
      for (const step of run.failedSteps ?? []) lines.push(`${run.name} ${run.url}: ${step}, with no check annotation`);
    }
    if (lines.length > before) runs.add(run.id);
  }
  if (lines.length === 0) return [];
  return [
    finding({
      key: "lane-variables",
      signal: "14 lane variables",
      title: "Lane variables: a repository variable changed outside the lane level, or the check could not read",
      area: "Lanes token (work-unblock publish-lane-level)",
      summary: `${runs.size} publish-lane-level runs in the last hour failed the repository variable check. Read each run, and set a changed variable back by hand.`,
      facts: lines,
      evidence: ["lane-variables", [...runs].map(String).sort()],
    }),
  ];
}

export const LANE_HOLDS = { threshold: 4, "window-hours": 24 };
const holdJobs = (workflow, entries) => {
  const listed = entries.map((entry) => listedJob(workflow, ...[entry].flat()));
  const earlier = listed.flatMap((job) => job.earlier);
  return { workflow, jobs: listed.map(({ id }) => id), names: listed.map(({ name }) => name), ...(earlier.length > 0 && { earlier }) };
};
export const HOLD_LANES = [
  { lane: "work-resolve-issue", ...holdJobs("work-resolve-issue.yml", [["report-outcome", "run"], "pick-slot"]), area: "Issue lane (work-resolve-issue)" },
  { lane: "work-unblock", ...holdJobs("work-unblock.yml", ["label-unblocked"]), area: "Unblock lane (work-unblock)", holdRuns: 20 },
  {
    lane: "pr-refine",
    ...holdJobs("pr-refine.yml", ["fix-docs-head-held", "fix-docs-handoff", "fix-docs-subscription-handoff", "record-passes"]),
    area: "PR refine lane (pr-refine fix-docs)",
    holdRuns: 12,
    statuses: ["success", "failure"],
  },
  { lane: "intake-triage", ...holdJobs("intake-triage.yml", ["apply-verdict"]), area: "Intake lane (intake-triage apply-verdict)", holdRuns: 40 },
  {
    lane: "pr-verify",
    ...holdJobs("pr-verify.yml", ["check-intent", "check-intent-subscription", "check-intent-fallback"]),
    area: "Verify lane (pr-verify)",
    holdRuns: 80,
    listPages: 5,
    holdStep: "Note the hold",
  },
  {
    lane: "pr-review-main",
    ...holdJobs("pr-review-main.yml", ["check-trigger", "review", "review-subscription", "review-fallback"]),
    area: "Review lanes (pr-review-main)",
    holdRuns: 70,
    listPages: 4,
    holdStep: "Note the hold",
  },
  { lane: "pr-merge", ...holdJobs("pr-merge.yml", ["merge", "enable-auto-merge"]), area: "Merge lane (pr-merge lane token)", holdRuns: 80, listPages: 5 },
];

export const holdJob = (jobs, name) => jobs.some((job) => name === job || String(name).startsWith(`${job} (`));
const NAME = "[a-z]+(?:-[a-z]+)*";
const HOLD_NOTICES = [
  { title: "report-outcome", pattern: new RegExp(`^issue #(\\d+) stopped on a fault \\((${NAME})\\), and every retry`), hold: (m) => ({ item: `#${m[1]}`, reason: `fault ${m[2]}` }) },
  { title: "label-unblocked", pattern: new RegExp(`^the (${NAME}) listing failed \\(`), hold: (m) => ({ item: null, reason: `${m[1]} listing failed` }) },
  { title: "label-unblocked", pattern: /^#(\d+): (?:.*\bstatus (\d{3})\b)?.*; holding, and the next sweep reads it again$/, hold: (m) => ({ item: `#${m[1]}`, reason: `read fault${m[2] ? ` HTTP ${m[2]}` : ""}` }) },
  { title: "Handoff evidence hold", pattern: new RegExp(`^handoff evidence for (${NAME}) still missing`), hold: (m) => ({ item: null, reason: `${m[1]} handoff evidence missing` }) },
  { title: "PR head hold", pattern: /^the head of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR head unread" }) },
  { title: "PR head hold", pattern: /^the human-gated hold of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR hold unread" }) },
  { title: "PR head hold", pattern: /^the changed files of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR files unread" }) },
  {
    title: "WIP cap hold",
    pattern: /^(?:WIP cap hold: the (base config) could not be read|WIP cap hold: the (open lane PRs) could not be listed|the (WIP cap check) did not finish), so the pause is unknown/,
    hold: (m) => ({ item: null, reason: m[1] ? "WIP cap base config unread" : m[2] ? "WIP cap open listing failed" : "WIP cap check unfinished" }),
  },
  {
    title: "pr-verify",
    pattern: /^held: (?:pr-verify's trigger gate met a GitHub fault|pr-verify could not resolve the pull request)/,
    hold: (m) => ({ item: null, reason: m[0].includes("trigger gate") ? "trigger gate fault" : "resolver fault" }),
  },
  { title: "pr-review-main", pattern: /^held: the file list did not read /, hold: () => ({ item: null, reason: "file list unread" }) },
  { title: "Lane token hold", pattern: /^lane-token-held: the broker answered 503 github-rate-limited /, hold: () => ({ item: null, reason: "lane token rate-limited" }) },
  { title: "apply-verdict", pattern: /^held: (admission failed: )?(?:.*\bstatus (\d{3})\b)?/, hold: (m) => ({ item: null, reason: `${m[1] ? "admission " : ""}fault${m[2] ? ` HTTP ${m[2]}` : ""}` }) },
  { title: "refine-failed", level: "warning", pattern: new RegExp(`^pass=(${NAME}) reason=(${NAME})$`), hold: (m) => ({ item: null, reason: `${m[1]} failed: ${m[2]}` }) },
];

export function parseHold(title, message, level = "notice") {
  for (const { title: t, level: l = "notice", pattern, hold } of HOLD_NOTICES) {
    const m = t === title && l === level ? pattern.exec(String(message)) : null;
    if (m) return hold(m);
  }
  return null;
}

export function holdRule(leaf) {
  const rule = { ...LANE_HOLDS, ...(leaf ?? {}) };
  const whole = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;
  if (!whole(rule.threshold, 2, 100) || !whole(rule["window-hours"], 1, 168)) {
    throw new Error("monitor.lane-holds needs a threshold of 2 to 100 and window-hours of 1 to 168");
  }
  return { threshold: rule.threshold, windowHours: rule["window-hours"] };
}

export function laneHoldFindings({ laneHolds = [], holdRule: rule = null }) {
  if (!rule) return [];
  const out = [];
  for (const { lane, area } of HOLD_LANES) {
    const holds = laneHolds.filter((h) => h.lane === lane).sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
    if (holds.length < rule.threshold) continue;
    const perItem = new Map();
    for (const { item } of holds) if (item) perItem.set(item, (perItem.get(item) ?? 0) + 1);
    const repeated = [...perItem].filter(([, n]) => n > 1).map(([item, n]) => `${item} ${n} times`);
    out.push(
      finding({
        key: `lane-hold:${lane}`,
        signal: "13 lane holds",
        title: `Lane holds: ${lane} held ${holds.length} runs in the last ${rule.windowHours} hours`,
        area,
        summary: `${holds.length} green ${lane} runs held on a fault in the last ${rule.windowHours} hours, at or over the threshold of ${rule.threshold}; each ended with only a notice and is retried later.${repeated.length > 0 ? ` Held more than once: ${repeated.join(", ")}.` : ""}`,
        facts: holds.map((h) => `${h.at}${h.item ? ` ${h.item}` : ""} ${h.url}: ${h.reason}`),
        evidence: [`lane-hold:${lane}`, [...new Set(holds.map((h) => masked(h.reason)))].sort()],
        observedAt: holds[0].at,
      }),
    );
  }
  return out;
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
  laneHoldFindings,
  laneVariableFindings,
];

export function detect(data) {
  const byKey = new Map();
  for (const detector of DETECTORS) {
    for (const f of detector(data)) if (!byKey.has(f.key)) byKey.set(f.key, f);
  }
  return [...byKey.values()];
}
