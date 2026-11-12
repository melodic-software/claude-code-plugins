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
const share = (r) => r.used / r.limit;
// Counts masked, so a fingerprint keeps still while the same cause recurs.
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

// Broker refusals from request-lane-token's annotations. workflow-modified is
// left out: pr-merge re-fires those runs on its schedule, and the feedback
// sweep sends a refused address-feedback round again.
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
        evidence: [key, failures.map((a) => masked(String(a.message))).sort()],
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

// pr-merge's open pull requests were unknown in each of its newest
// LISTING_HELD_SWEEPS sweeps, so the job gates nothing while its runs end green
// with only a notice. It only notifies; a sweep that lists clears it. The
// fingerprint is the newest reason with its counts masked, so a cause that
// holds is written once.
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

// work-unblock's publish-lane-level fails red when the lane token's Variables
// write changed any repository variable but the level variable, or when its
// check could not list them (publish-lane-level.mjs check). Either is a
// security signal: a repository variable can shadow an organization one, such
// as the lanes kill switch. collect's "lane variable runs" source keeps only
// main's failed scheduled work-unblock runs, and only their failed
// publish-lane-level job, so the event and workflow are checked there. A
// variable step that ended without success and with no annotation (a timeout)
// counts too: a check that did not finish must not read as clear.
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

// The lanes whose read faults hold green with only a notice (outage posture
// element 2), the jobs that print each hold notice, and that notice. A lane
// that passes the threshold of docs/conventions/pr-pipeline.yaml
// monitor.lane-holds raises signal 13; the leaf's defaults have this one copy.
// Each lane's `jobs` are those jobs' ids, and `names` their names in the same
// order, as a run lists them; a run from before the job rename lists the ids.
// `holdRuns`, when set, is the lane's own cap on unread green runs per window
// (collect.mjs LIMITS.holdRuns otherwise).
export const LANE_HOLDS = { threshold: 4, "window-hours": 24 };
export const HOLD_LANES = [
  { lane: "work-resolve-issue", workflow: "work-resolve-issue.yml", jobs: ["report-outcome / run", "pick-slot"], names: ["Report Outcome / Run", "Pick Slot"], area: "Issue lane (work-resolve-issue)" },
  // The 24 hours to 2026-11-05T22:00Z had 165 green runs, a mean of 6.9 an
  // hour over the default cap of 6, and a peak of 51; 20 covers every hour
  // but that one, whose rest later runs read.
  { lane: "work-unblock", workflow: "work-unblock.yml", jobs: ["label-unblocked"], names: ["Label Unblocked"], area: "Unblock lane (work-unblock)", holdRuns: 20 },
  // A failed Refine pass reds its run, so this lane's red runs are read too,
  // for record-passes's refine-failed warning.
  {
    lane: "pr-refine",
    workflow: "pr-refine.yml",
    jobs: ["fix-docs-head-held", "fix-docs-handoff", "fix-docs-subscription-handoff", "record-passes"],
    names: ["Fix Docs Head Held", "Fix Docs Handoff", "Fix Docs Subscription Handoff", "Record Passes"],
    area: "PR refine lane (pr-refine fix-docs)",
    statuses: ["success", "failure"],
  },
  // One run per triaged issue: the 7 days to 2026-11-05 had a mean of 9.9
  // green runs per 65-minute window and a peak of 49; 40 leaves 2 of 168
  // windows over it.
  { lane: "intake-triage", workflow: "intake-triage.yml", jobs: ["apply-verdict"], names: ["Apply Verdict"], area: "Intake lane (intake-triage apply-verdict)", holdRuns: 40 },
  // One run per checks run: the 24 hours to 2026-11-06T12:00Z had 504 green
  // runs, a peak of 58 created in one hour and 267 in one 7-hour created span.
  // 80 a window and 5 list pages leave headroom over both; only a job whose
  // `Note the hold` step ran has its annotations read (`holdStep`), so a run
  // costs one REST jobs read for the steps.
  {
    lane: "pr-verify",
    workflow: "pr-verify.yml",
    jobs: ["check-intent", "check-intent-subscription", "check-intent-fallback"],
    names: ["Check Intent", "Check Intent Subscription", "Check Intent Fallback"],
    area: "Verify lane (pr-verify)",
    holdRuns: 80,
    listPages: 5,
    holdStep: "Note the hold",
  },
  // One run per pr-require-checks run, as pr-verify: 425 green runs on
  // 2026-11-05. Scaled by pr-verify's measured shape (a peak hour 2.8 times
  // its mean, a peak 7-hour created span 53% of its day), that is about 50
  // an hour and 225 a span, so 70 a window and 4 list pages leave headroom.
  // The legs are matrix jobs, listed as `Review (claude-review, ...)`, so a
  // job matches by name or as a matrix leg (holdJob); only a job whose
  // `Note the hold` ran has its annotations read.
  {
    lane: "pr-review-main",
    workflow: "pr-review-main.yml",
    jobs: ["trigger", "review", "review-subscription", "review-fallback"],
    names: ["Trigger", "Review", "Review Subscription", "Review Fallback"],
    area: "Review lanes (pr-review-main)",
    holdRuns: 70,
    listPages: 4,
    holdStep: "Note the hold",
  },
  // pr-merge's two token steps (rate-limit-hold-ok) hold on a rate limit the
  // lane-token request could not wait out. Its runs are the 2 cron ticks an
  // hour, one per main push (whose merge and enable-auto-merge jobs skip),
  // one wake per pr-verify pass, a share of pr-verify's runs, and one per
  // label removal, a count not measured (UNVERIFIED); pr-verify's 80 a window
  // and 5 list pages are taken as the cover. No step runs only on a hold, so
  // each green job's annotations are read.
  { lane: "pr-merge", workflow: "pr-merge.yml", jobs: ["merge", "enable-auto-merge"], names: ["Merge", "Enable Auto Merge"], area: "Merge lane (pr-merge lane token)", holdRuns: 80, listPages: 5 },
];

// Whether a listed job is one of `jobs`: by name, or as a matrix leg of one,
// which GitHub lists as `<job> (<matrix values>)`.
export const holdJob = (jobs, name) => jobs.some((job) => name === job || String(name).startsWith(`${job} (`));
const NAME = "[a-z]+(?:-[a-z]+)*";
const HOLD_NOTICES = [
  // report-outcome.mjs: a fault stop whose counted retries were all faults.
  { title: "report-outcome", pattern: new RegExp(`^issue #(\\d+) stopped on a fault \\((${NAME})\\), and every retry`), hold: (m) => ({ item: `#${m[1]}`, reason: `fault ${m[2]}` }) },
  // label-unblocked.mjs reportHold: a listing the sweep could not read.
  { title: "label-unblocked", pattern: new RegExp(`^the (${NAME}) listing failed \\(`), hold: (m) => ({ item: null, reason: `${m[1]} listing failed` }) },
  // label-unblocked.mjs failedFor: one issue's read met a GitHub fault. The
  // reason names only the status, never the fault's text.
  { title: "label-unblocked", pattern: /^#(\d+): (?:.*\bstatus (\d{3})\b)?.*; holding, and the next sweep reads it again$/, hold: (m) => ({ item: `#${m[1]}`, reason: `read fault${m[2] ? ` HTTP ${m[2]}` : ""}` }) },
  // handoff-evidence.sh: a fix-docs read that failed.
  { title: "Handoff evidence hold", pattern: new RegExp(`^handoff evidence for (${NAME}) still missing`), hold: (m) => ({ item: null, reason: `${m[1]} handoff evidence missing` }) },
  // pr-refine.yml fix-docs-head-held: the PR head, or its human-gated hold
  // (lane-hold.mjs), could not be read.
  { title: "PR head hold", pattern: /^the head of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR head unread" }) },
  { title: "PR head hold", pattern: /^the human-gated hold of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR hold unread" }) },
  // pr-refine.yml fix-docs-head-held after a plan hold: the PR's changed
  // files could not be read.
  { title: "PR head hold", pattern: /^the changed files of #(\d+) could not be read/, hold: (m) => ({ item: `#${m[1]}`, reason: "PR files unread" }) },
  // check-wip-cap.mjs, or pick-slot's step when the check did not finish: the
  // pause could not be read, so the run started no work. A fixed reason per
  // cause, and no item, since the hold is the lane's, not one issue's.
  {
    title: "WIP cap hold",
    pattern: /^(?:WIP cap hold: the (base config) could not be read|WIP cap hold: the (open lane PRs) could not be listed|the (WIP cap check) did not finish), so the pause is unknown/,
    hold: (m) => ({ item: null, reason: m[1] ? "WIP cap base config unread" : m[2] ? "WIP cap open listing failed" : "WIP cap check unfinished" }),
  },
  // pr-verify: resolve-pr.mjs closing, or pr-verify.yml's `Note the hold` for
  // a trigger gate stopped with read-fault. A fixed reason per cause, and no
  // item: the PR is the run's, read from its URL.
  {
    title: "pr-verify",
    pattern: /^held: (?:pr-verify's trigger gate met a GitHub fault|pr-verify could not resolve the pull request)/,
    hold: (m) => ({ item: null, reason: m[0].includes("trigger gate") ? "trigger gate fault" : "resolver fault" }),
  },
  // pr-review-main.yml's four `Select a lane-source pull request` steps: the
  // file list did not read after retry_call's 3 reads.
  { title: "pr-review-main", pattern: /^held: the file list did not read /, hold: () => ({ item: null, reason: "file list unread" }) },
  // request-lane-token's rate-limit-hold-ok: the broker's last answer was a
  // rate limit, whether the budget or the 3 requests ended the retries. One
  // fixed reason, never the notice's reset time.
  { title: "Lane token hold", pattern: /^lane-token-held: the broker answered 503 github-rate-limited /, hold: () => ({ item: null, reason: "lane token rate-limited" }) },
  // apply-verdict.mjs closing: a GitHub fault held the verdict. The reason is
  // a closed set, never the fault's own text, so the finding's fingerprint
  // stays put; the issue a path names may be a blocker, so no item.
  { title: "apply-verdict", pattern: /^held: (admission failed: )?(?:.*\bstatus (\d{3})\b)?/, hold: (m) => ({ item: null, reason: `${m[1] ? "admission " : ""}fault${m[2] ? ` HTTP ${m[2]}` : ""}` }) },
  // log-pass-records.mjs: a Refine pass that failed. A warning, since the
  // pass did not hold but failed; its reason is already a closed set.
  { title: "refine-failed", level: "warning", pattern: new RegExp(`^pass=(${NAME}) reason=(${NAME})$`), hold: (m) => ({ item: null, reason: `${m[1]} failed: ${m[2]}` }) },
];

// One annotation's hold, {item, reason}, or null. Each entry matches one
// level, notice unless it names another.
export function parseHold(title, message, level = "notice") {
  for (const { title: t, level: l = "notice", pattern, hold } of HOLD_NOTICES) {
    const m = t === title && l === level ? pattern.exec(String(message)) : null;
    if (m) return hold(m);
  }
  return null;
}

// The monitor.lane-holds leaf as set ({} when absent), with its defaults, or a
// throw for a value the schema refuses.
export function holdRule(leaf) {
  const rule = { ...LANE_HOLDS, ...(leaf ?? {}) };
  const whole = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;
  if (!whole(rule.threshold, 2, 100) || !whole(rule["window-hours"], 1, 168)) {
    throw new Error("monitor.lane-holds needs a threshold of 2 to 100 and window-hours of 1 to 168");
  }
  return { threshold: rule.threshold, windowHours: rule["window-hours"] };
}

// A held run ends green with only a notice, so a fault that holds every run
// shows nowhere else. One finding per lane whose held runs over the rule's
// window reach its threshold; an issue held that often is one of them. It only
// notifies, adds no stop and clears once the count drops below the threshold.
// The fingerprint is the set of hold reasons with counts masked, so a fault
// that keeps holding is written once.
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
