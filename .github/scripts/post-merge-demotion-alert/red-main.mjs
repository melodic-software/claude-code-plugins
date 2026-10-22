// The red-main rule as pure functions: when a red full run on main counts as
// confirmed, which merge in the failing range is the culprit, whether the bot
// may revert it, and the report. docs/conventions/pr-pipeline/README.md,
// "Red main", states the rule; report.mjs reads GitHub and calls these.

// The `red-main` leaf of pr-pipeline.yaml (pr-pipeline.schema.json); the one
// copy of its defaults.
export const RED_MAIN_DEFAULTS = Object.freeze({
  "dry-run": true,
  "daily-cap": 3,
  "max-culprit-age-hours": 24,
  "confirm-wait-minutes": 40,
  remedy: "rollback",
});

const VALID = {
  "dry-run": (value) => typeof value === "boolean",
  "daily-cap": (value) => Number.isInteger(value) && value >= 0 && value <= 10,
  "max-culprit-age-hours": (value) => Number.isInteger(value) && value >= 1 && value <= 168,
  "confirm-wait-minutes": (value) => Number.isInteger(value) && value >= 0 && value <= 45,
  remedy: (value) => value === "rollback" || value === "fail-forward",
};

// Every leaf, each valid set value over its default.
export const resolveRedMain = (leaf) =>
  Object.fromEntries(
    Object.entries(RED_MAIN_DEFAULTS).map(([key, value]) => [key, VALID[key](leaf?.[key]) ? leaf[key] : value]),
  );

const AGGREGATOR_STEP = "Aggregate hygiene results";
// The all-branches secret scan fails on any branch, so it counts against no merge.
const BRANCH_WIDE_GATES = new Set(["gitleaks failed"]);

// The checks a run attempt failed, as post-merge-demotion-alert.yml's
// failing_checks names them: a job, or `job: gate` for each gate the hygiene
// aggregator titles in a failure annotation. Only a job that concluded
// `failure` counts: a cancelled or timed-out job is no evidence of a break.
// `annotations` maps a job id to its annotations.
export function failingChecks(jobs, annotations = {}) {
  const failed = jobs.filter((job) => job.conclusion === "failure");
  const checks = [];
  for (const job of failed) {
    if (job.name === "ci-status" && failed.length > 1) continue;
    const gates = (annotations[job.id] ?? [])
      .filter((a) => a.annotation_level === "failure" && (a.title ?? "").length > 0)
      .map((a) => a.title);
    const otherSteps = (job.steps ?? []).filter(
      (step) => ["failure", "timed_out", "cancelled"].includes(step.conclusion) && step.name !== AGGREGATOR_STEP,
    ).length;
    if (gates.length === 0 || otherSteps > 0) checks.push(job.name);
    for (const gate of gates) {
      if (!BRANCH_WIDE_GATES.has(gate)) checks.push(`${job.name}: ${gate}`);
    }
  }
  return [...new Set(checks)];
}

const intersect = (a, b) => a.filter((item) => b.includes(item));

// A red full run is confirmed when attempt 1 failed, a later attempt (the one
// re-run of the failed jobs) finished and failed too, and at least one check
// failed in both. `first` and `latest` are { attempt, conclusion, checks }.
export function confirm(first, latest) {
  if (!latest || latest.attempt < 2) {
    return { confirmed: false, reason: "no re-run of the failed jobs finished", checks: [] };
  }
  if (first.conclusion !== "failure") {
    return { confirmed: false, reason: `attempt 1 concluded ${first.conclusion}, not failure`, checks: [] };
  }
  if (latest.conclusion !== "failure") {
    return {
      confirmed: false,
      reason: `the re-run (attempt ${latest.attempt}) concluded ${latest.conclusion}, not failure`,
      checks: [],
    };
  }
  const checks = intersect(first.checks, latest.checks);
  if (checks.length === 0) {
    return { confirmed: false, reason: "the re-run failed, but in no check attempt 1 failed", checks: [] };
  }
  return { confirmed: true, reason: `attempts 1 and ${latest.attempt} both failed`, checks };
}

// The first-parent chain from `base` (exclusive) to `head`, oldest first, from
// compare's commits ({ sha, parent }); null when the chain does not reach base.
export function firstParentRange(base, head, commits, limit = 50) {
  const parentOf = new Map(commits.map((c) => [c.sha, c.parent]));
  const range = [];
  for (let at = head; at !== base; at = parentOf.get(at)) {
    if (!parentOf.has(at) || range.length >= limit) return null;
    range.unshift(at);
  }
  return range;
}

// One commit's evidence from its own full run: `green` (passed, on any
// attempt), `red` (confirmed red in a check the head's confirmed red also
// failed), `red-unconfirmed` (failed with no matching confirmed re-run), or
// `untested` (no full run finished at that commit).
export function commitStatus(run, headChecks) {
  if (!run) return "untested";
  if (run.conclusion === "success") return "green";
  if (run.conclusion !== "failure") return "untested";
  const verdict = confirm(run.first, run.latest);
  return verdict.confirmed && intersect(verdict.checks, headChecks).length > 0 ? "red" : "red-unconfirmed";
}

// The culprit: the one commit in the range that is red while its parent
// (base for the oldest) is green. Anything else pins no culprit.
export function attribute(base, range, statuses) {
  const status = (sha) => (sha === base ? "green" : (statuses[sha] ?? "untested"));
  const transitions = range.filter((sha, i) => status(sha) === "red" && status(i === 0 ? base : range[i - 1]) === "green");
  const untested = range.filter((sha) => status(sha) === "untested");
  if (transitions.length === 1) return { culprit: transitions[0], transitions, untested, reason: "" };
  return {
    culprit: null,
    transitions,
    untested,
    reason:
      transitions.length > 1
        ? `${transitions.length} merges each fail where their parent passes`
        : "no merge in the range fails where its parent passes on the evidence runs",
  };
}

export const isRevert = (message, labels = []) =>
  /^revert\b/i.test(message) || /This reverts commit [0-9a-f]{7,40}/.test(message) || labels.includes("auto-revert");

// Whether the bot may revert the culprit itself, and every guard that sends it
// to a person instead. Owner and other human merges never auto-revert: only a
// merge the lanes App put in the merge queue may. Under the fail-forward
// remedy nothing is reverted.
export function decide({ culprit, agentIdentity, config, now, revertsToday, culpritDecided, platformFault, revertApplies }) {
  if (config.remedy === "fail-forward") {
    return { decision: "human", reasons: ["the remedy is fail-forward: a person or a fix pull request repairs main"] };
  }
  const reasons = [];
  if (!agentIdentity || (culprit.enqueuer ?? "").toLowerCase() !== agentIdentity.toLowerCase()) {
    reasons.push(`put in the merge queue by ${culprit.enqueuer || "an unknown actor"}, not the lanes App`);
  }
  const ageHours = (Date.parse(now) - Date.parse(culprit.mergedAt)) / 3_600_000;
  if (!Number.isFinite(ageHours)) {
    reasons.push("its merge time could not be read");
  } else if (ageHours >= config["max-culprit-age-hours"]) {
    reasons.push(`merged ${Math.floor(ageHours)} h ago, at or past max-culprit-age-hours (${config["max-culprit-age-hours"]})`);
  }
  if (isRevert(culprit.message, culprit.labels)) reasons.push("it is itself a revert");
  if (culpritDecided) reasons.push("an auto-revert of this merge was already decided");
  if (revertsToday >= config["daily-cap"]) {
    reasons.push(`${revertsToday} auto-reverts in the last 24 h reach daily-cap (${config["daily-cap"]})`);
  }
  if (platformFault) reasons.push(`a platform fault is suspected: ${platformFault}`);
  if (revertApplies === false) reasons.push("the revert does not apply cleanly to main's tip");
  if (revertApplies === null) reasons.push("whether the revert applies to main's tip could not be read");
  return { decision: reasons.length === 0 ? "auto-revert" : "human", reasons };
}

export const LOG_MARKER = "<!-- red-main-revert-log -->";
export const reportMarker = ({ runId, attempt, culprit, decision }) =>
  `<!-- red-main-report run=${runId} attempt=${attempt} culprit=${culprit ?? "none"} decision=${decision} -->`;
export const MARKER_PATTERN =
  /^<!-- red-main-report run=(\d+) attempt=(\d+) culprit=([0-9a-f]{40}|none) decision=(auto-revert|human|none) -->$/;

// Text from commits and pull requests reaches the report only as inert lines
// inside a text fence.
const inert = (text) => String(text ?? "").replaceAll("`", "'").split("\n")[0];

const SUBJECT_PR = /\s*\(#(\d+)\)$/;

// The revert the bot would open for the culprit, as the report names it.
export function plannedRevert(culprit, decision, runUrl) {
  const subject = inert(culprit.message).replace(SUBJECT_PR, "");
  const pr = culprit.number ? `#${culprit.number}` : culprit.sha.slice(0, 12);
  return {
    branch: `red-main-revert/${culprit.sha.slice(0, 12)}`,
    command: `git revert --no-edit ${culprit.sha}`,
    title: `revert: ${subject}`,
    draft: decision !== "auto-revert",
    labels: decision === "auto-revert" ? ["auto-revert"] : ["auto-revert", "needs-human"],
    bodyMarker: `<!-- red-main-revert culprit=${culprit.sha} -->`,
    reinstate: `Reinstate ${pr} after its red-main revert`,
    notify: culprit.number ? `a comment on #${culprit.number} linking ${runUrl}` : "none: the merge names no pull request",
    merge:
      decision === "auto-revert"
        ? "the bot enqueues it in the merge queue once its checks pass"
        : "a person reviews and merges it",
  };
}

// The report: a marker line, then Markdown. `range` rows are
// { sha, number, enqueuer, status, evidence }.
export function renderReport({ run, verdict, base, range, attribution, culprit, decision, revert, config, record }) {
  const lines = [
    reportMarker({
      runId: run.id,
      attempt: run.attempt,
      culprit: culprit?.sha,
      decision: decision?.decision ?? "none",
    }),
    "",
    `### Red main at \`${run.sha.slice(0, 12)}\`: ${decision ? (decision.decision === "auto-revert" ? "the bot would auto-revert" : "a person decides") : "no culprit"}`,
    "",
    `Mode: ${config["dry-run"] ? "dry-run" : "dry-run off, but this version only reports"}; nothing was pushed, opened or merged.`,
    "",
    `- Failing run: ${run.url}/attempts/${run.attempt} (${verdict.reason})`,
    `- Failing in both attempts: ${verdict.checks.map((c) => `\`${inert(c)}\``).join(", ")}`,
    `- Last green full run: ${base ? `\`${base.sha}\` (${base.url})` : "not found"}`,
  ];
  if (record) lines.push(`- Post-merge record: #${record}`);
  if (range) {
    lines.push("", "| Merge | Pull request | Queued by | Evidence | Status |", "|---|---|---|---|---|");
    for (const row of range) {
      lines.push(
        `| \`${row.sha.slice(0, 12)}\` | ${row.number ? `#${row.number}` : "none"} | ${inert(row.enqueuer) || "unknown"} | ${row.evidence ?? "none"} | ${row.status} |`,
      );
    }
  } else {
    lines.push("", "No culprit: the merges since the last green full run could not be read, or number more than 25.");
  }
  if (attribution && !attribution.culprit) {
    lines.push("", `No culprit: ${attribution.reason}.`);
    if (attribution.untested.length > 0) {
      lines.push(
        `To pin one, the bot would run the full suite at each untested merge (${attribution.untested.map((s) => `\`${s.slice(0, 12)}\``).join(", ")}) by dispatching pr-require-checks on a branch at that commit.`,
      );
    }
    lines.push("No revert pull request: a person picks the merge from the post-merge record.");
  }
  if (culprit && decision) {
    lines.push(
      "",
      `Culprit: \`${culprit.sha}\`${culprit.number ? ` (#${culprit.number})` : ""}, merged ${culprit.mergedAt}, fails where its parent passes.`,
    );
    if (decision.reasons.length > 0) {
      lines.push("", "A person decides because:", ...decision.reasons.map((r) => `- ${r}`));
    }
  }
  if (revert) {
    lines.push(
      "",
      `The revert it would open${revert.draft ? " (draft)" : ""}:`,
      "",
      "```text",
      `branch:    ${revert.branch}`,
      `command:   ${revert.command}`,
      `title:     ${revert.title}`,
      `labels:    ${revert.labels.join(", ")}`,
      `body:      ${revert.bodyMarker}, Refs the culprit, the failing run and the evidence above`,
      `reinstate: an issue titled "${revert.reinstate}"`,
      `notify:    ${revert.notify}`,
      `merge:     ${revert.merge}`,
      "```",
    );
  }
  return lines.join("\n");
}
