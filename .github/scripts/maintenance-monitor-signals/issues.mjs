// The monitoring lane's incident issues, found by the marker on their first
// body line: at most one open per signal, filed only once the signal has
// stayed on past its open threshold and closed once it has stayed clear past
// its close threshold (pr-pipeline.yaml monitor.incidents). A state change
// rewrites the body and adds no comment. Every run's status goes to the job
// summary. Platform incidents are logged there and never filed. The earlier
// rolling issues still open are retired. No network.
import { createHash } from "node:crypto";

export const SIGNALS = [
  "1 main red",
  "2 ceiling",
  "3 throttling",
  "4 merge-queue ejections",
  "5 held PRs",
  "6 report-only audit",
  "8 throughput",
  "9 lane stop",
  "10 stalled lane stop",
  "11 post-merge unreadable",
  "12 listing held",
  "13 lane holds",
];
export const LOG_ONLY = new Set(["7 platform incident"]);
const MUTED = new Set(["not_planned", "duplicate"]);
const MARKER = /^<!-- factory-monitor key=([a-z0-9][a-z0-9:._-]{0,79}) fp=([0-9a-f]{16}) -->$/;
const INCIDENT = "incident:";

// The issue a signal files: a plain title, as docs/standards/issue-tracker.md
// "Issue titles" asks, and the Priority field's value. Priority follows the
// intake rubric: a red main is critical, what blocks the pipeline is high.
export const FILING = {
  "1 main red": { title: "Restore the failing required checks on main", priority: "critical" },
  "2 ceiling": { title: "Bring API or Actions usage back under its ceiling", priority: "high" },
  "3 throttling": { title: "Stop the lanes being throttled or refused tokens", priority: "high" },
  "4 merge-queue ejections": { title: "Find why the merge queue keeps ejecting groups", priority: "high" },
  "5 held PRs": { title: "Clear the pull requests held for over a day", priority: "medium" },
  "6 report-only audit": { title: "Fix the failing report-only audit", priority: "medium" },
  "8 throughput": { title: "Find why no lane pull request is merging", priority: "high" },
  "9 lane stop": { title: "Find why issue lane runs keep stopping", priority: "medium" },
  "10 stalled lane stop": { title: "Clear the stalled lane stops on open pull requests", priority: "medium" },
  "11 post-merge unreadable": { title: "Restore the post-merge check's read of lane merges", priority: "high" },
  "12 listing held": { title: "Restore the merge job's listing of open pull requests", priority: "high" },
  "13 lane holds": { title: "Find why a lane keeps holding its runs", priority: "medium" },
};

export const familyOf = (signal) =>
  String(signal)
    .replace(/^\d+ /, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-");
const incidentKey = (signal) => `${INCIDENT}${familyOf(signal)}`;

export function readMarker(body) {
  const m = MARKER.exec(String(body ?? "").split("\n", 1)[0]);
  return m ? { key: m[1], fingerprint: m[2] } : null;
}

// The incident's state: its findings' keys, which change only when what is
// wrong changes, so a body an admission read stays as it was while the same
// fault goes on. No finding is the clear state.
export const stateFingerprint = (findings) =>
  createHash("sha256")
    .update(JSON.stringify(findings.map((f) => f.key).sort()))
    .digest("hex")
    .slice(0, 16);

// Run, job, status-page and URL text is data: inside a fence longer than any
// backtick run it holds, no mention, link, reference or tag works.
export const fenced = (lines) => {
  const body = lines.join("\n");
  const fence = "`".repeat(Math.max(3, ...(body.match(/`+/g) ?? []).map((run) => run.length + 1)));
  return `${fence}text\n${body}\n${fence}`;
};

export function renderBody({ signal, findings }, runUrl) {
  const state =
    findings.length === 0
      ? `**State:** clear in [this run](${runUrl}).`
      : `**State:** ${findings.length} current finding${findings.length === 1 ? "" : "s"} in [this run](${runUrl}).`;
  return [
    `<!-- factory-monitor key=${incidentKey(signal)} fp=${stateFingerprint(findings)} -->`,
    `**Signal:** ${signal}`,
    state,
    "",
    "The monitoring lane filed this incident because the signal stayed on past its open threshold. Each hourly run's job summary holds the signal's current state and evidence. The lane rewrites this body only when the findings' keys change, and closes the issue once the signal stays clear past its close threshold. Closing it as not planned or duplicate mutes the signal; reopening it ends the mute.",
    ...findings.flatMap((f) => [
      "",
      `### \`${f.key}\``,
      "",
      `**Owning area:** ${f.area}`,
      "",
      fenced([f.summary]),
      ...(f.facts.length > 0 ? ["", fenced(f.facts)] : []),
    ]),
    "",
    "## Done when",
    "",
    "- [ ] The cause of the findings above is fixed.",
    "- [ ] The monitoring lane reports this signal clear past its close threshold.",
  ].join("\n");
}

export const renderRetire = (runUrl) =>
  `The monitoring lane no longer keeps a rolling issue per signal: [each run's job summary](${runUrl}) shows every signal's state, and a signal that stays on past its threshold files one incident issue. Closing this issue; its history stays here.`;

// The thresholds for every signal from pr-pipeline.yaml's monitor.incidents,
// keyed by signal, or a throw naming what is missing or out of range.
export function incidentRules(raw) {
  const rules = {};
  const hours = (value, name) => {
    if (!Number.isInteger(value) || value < 0) throw new Error(`monitor.incidents ${name} is not a whole number of hours`);
    return value;
  };
  for (const signal of SIGNALS) {
    const slug = familyOf(signal);
    rules[signal] = { open: hours(raw?.[slug]?.["open-hours"], `${slug} open-hours`), close: hours(raw?.[slug]?.["close-hours"], `${slug} close-hours`) };
  }
  return rules;
}

// The signals each collect source feeds, by the name collect gives its gap.
const SOURCES = {
  "pr-merge api budget": ["2 ceiling", "3 throttling"],
  "lane api budget": ["2 ceiling", "3 throttling"],
  "Actions jobs in use": ["2 ceiling"],
  "failed runs": ["3 throttling"],
  "main full run": ["1 main red"],
  "merge-queue ejections": ["4 merge-queue ejections"],
  "pr-merge sweep": ["3 throttling", "5 held PRs", "8 throughput", "12 listing held"],
  "pr-merge listed sweep": ["5 held PRs", "8 throughput"],
  "lane merges": ["8 throughput"],
  "lane stops": ["9 lane stop"],
  "stalled stops": ["10 stalled lane stop"],
  "post-merge reports": ["11 post-merge unreadable"],
  "lane holds": ["13 lane holds"],
  audits: ["6 report-only audit"],
  "githubstatus.com": [],
};

// The signals a run's gaps leave partly unread. A gap from a source not
// named above leaves every signal unread.
export function unreadSignals(gaps = []) {
  const unread = new Set();
  for (const gap of gaps) {
    const source = Object.keys(SOURCES).find((name) => String(gap).startsWith(`${name}:`));
    for (const signal of source ? SOURCES[source] : SIGNALS) unread.add(signal);
  }
  return unread;
}

const hoursSince = (iso, now) => (now.getTime() - Date.parse(iso)) / 3600_000;
const inHours = (hours) => `${Math.round(hours * 10) / 10}h`;

// existing: every issue the lane's two identities filed, any state, carrying
// a marker. episodes: the last run's {signal: {onSince, clearSince}}, empty
// when no carry was read, so a timer restarts: an issue opens later, never
// earlier. unread: signals a source failed for, whose timers and issue stay as
// they are. rules: incidentRules. The result's `episodes` is what the next
// run carries; `status` is one line of state per signal for the job summary.
export function planIssues({ findings, existing, unread = new Set(), rules, episodes = {}, now = new Date() }) {
  const bySignal = new Map(SIGNALS.map((s) => [s, []]));
  const logged = [];
  const unknown = [];
  for (const f of findings) {
    if (LOG_ONLY.has(f.signal)) logged.push(f);
    else if (bySignal.has(f.signal)) bySignal.get(f.signal).push(f);
    else unknown.push({ family: familyOf(f.signal), number: null, reason: "unknown signal" });
  }
  const incidents = new Map();
  const retire = [];
  for (const issue of existing) {
    const marker = readMarker(issue.body);
    if (!marker) continue;
    if (!marker.key.startsWith(INCIDENT)) {
      if (issue.state === "open") retire.push({ number: issue.number, key: marker.key });
      continue;
    }
    const seen = incidents.get(marker.key);
    if (!seen || issue.number > seen.issue.number) incidents.set(marker.key, { issue, marker });
  }

  const nowIso = now.toISOString();
  const plan = { file: [], update: [], close: [], retire: retire.sort((a, b) => a.number - b.number), skip: unknown, logged, status: [], episodes: {} };
  for (const [signal, list] of bySignal) {
    const family = { signal, findings: [...list].sort((a, b) => a.key.localeCompare(b.key)) };
    const on = family.findings.length > 0;
    const read = !unread.has(signal);
    const match = incidents.get(incidentKey(signal));
    const open = match?.issue.state === "open";
    const prior = episodes[signal] ?? {};
    let onSince = prior.onSince ?? null;
    let clearSince = prior.clearSince ?? null;
    if (read) {
      onSince = on ? (onSince ?? nowIso) : null;
      clearSince = on || !open ? null : (clearSince ?? nowIso);
    }
    if (onSince || clearSince) plan.episodes[signal] = { onSince, clearSince };

    const rule = rules[signal];
    const number = match?.issue.number ?? null;
    const unchanged = match?.marker.fingerprint === stateFingerprint(family.findings);
    const onFor = hoursSince(onSince, now);
    const clearFor = hoursSince(clearSince, now);
    const report = (state) => plan.status.push({ signal, on, state, findings: family.findings });
    const skip = (reason, state) => {
      plan.skip.push({ family: familyOf(signal), number, reason });
      report(state);
    };
    if (!read) {
      skip("not read", `not read${number ? `, #${number} left as it is` : ""}`);
    } else if (open) {
      if (on) {
        if (unchanged) skip("unchanged", `on, incident #${number} unchanged`);
        else {
          plan.update.push({ number, family });
          report(`on, incident #${number} updated`);
        }
      } else if (clearFor >= rule.close) {
        plan.close.push({ number, family });
        report(`clear for ${inHours(clearFor)}, closing incident #${number}`);
      } else {
        skip("clearing", `clear for ${inHours(clearFor)} of ${rule.close}h, incident #${number} stays open`);
      }
    } else if (match && MUTED.has(match.issue.state_reason)) {
      if (on) skip("muted", `on, muted by #${number}`);
      else report(`clear, muted by #${number}`);
    } else if (!on) {
      report("clear");
    } else if (
      unchanged &&
      Date.parse(onSince) <= Date.parse(match.issue.closed_at) &&
      !family.findings.some((f) => Date.parse(f.observedAt) > Date.parse(match.issue.closed_at))
    ) {
      skip("closed-unchanged", `on, unchanged since #${number} was closed`);
    } else if (onFor >= rule.open) {
      plan.file.push({ family });
      report(`on for ${inHours(onFor)}, filing an incident`);
    } else {
      skip("below threshold", `on for ${inHours(onFor)} of ${rule.open}h, no incident yet`);
    }
  }
  return plan;
}
