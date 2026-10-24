// The monitoring lane's issues: one rolling issue per signal family, found by
// the marker on its first body line, its body rewritten and a comment added
// only when the family's state changes. Platform incidents are logged in the
// run summary, never filed. Issues from the earlier one-issue-per-key scheme
// that are still open are closed, pointing at the family's rolling issue. No
// network.
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
];
export const LOG_ONLY = new Set(["7 platform incident"]);
const MUTED = new Set(["not_planned", "duplicate"]);
const MARKER = /^<!-- factory-monitor key=([a-z0-9][a-z0-9:._-]{0,79}) fp=([0-9a-f]{16}) -->$/;
const FAMILY = "family:";
// The signal a key from the one-issue-per-key scheme belonged to.
const LEGACY = [
  [/^main-red:/, "1 main red"],
  [/^ceiling:/, "2 ceiling"],
  [/^(?:throttle|broker-deny):/, "3 throttling"],
  [/^merge-queue-ejections$/, "4 merge-queue ejections"],
  [/^held-over-24h$/, "5 held PRs"],
  [/^audit:/, "6 report-only audit"],
  [/^platform:/, "7 platform incident"],
  [/^throughput-zero$/, "8 throughput"],
  [/^lane-stop:/, "9 lane stop"],
];

export const familyOf = (signal) =>
  String(signal)
    .replace(/^\d+ /, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-");
const familyKey = (signal) => `${FAMILY}${familyOf(signal)}`;
const label = (signal) => String(signal).replace(/^\d+ /, "");
const legacySignal = (key) => LEGACY.find(([re]) => re.test(key))?.[1] ?? null;

export function readMarker(body) {
  const m = MARKER.exec(String(body ?? "").split("\n", 1)[0]);
  return m ? { key: m[1], fingerprint: m[2] } : null;
}

// The family's state: its findings' keys and fingerprints. No finding is the
// clear state.
export const stateFingerprint = (findings) =>
  createHash("sha256")
    .update(JSON.stringify(findings.map((f) => [f.key, f.fingerprint]).sort()))
    .digest("hex")
    .slice(0, 16);

export const titleOf = (signal) => `Monitoring: ${label(signal)}`;

const evidence = (finding) => ["```text", ...finding.facts, "```"].join("\n");

export function renderBody({ signal, findings }, runUrl) {
  const state =
    findings.length === 0
      ? `**State:** clear in [this run](${runUrl}).`
      : `**State:** ${findings.length} current finding${findings.length === 1 ? "" : "s"} in [this run](${runUrl}).`;
  return [
    `<!-- factory-monitor key=${familyKey(signal)} fp=${stateFingerprint(findings)} -->`,
    `**Signal:** ${signal}`,
    state,
    "",
    "The monitoring lane keeps this one issue for the signal. A run that changes its state rewrites this body and adds a comment; the lane closes it when the signal clears and reopens it when the signal fires again. Closing it as not planned or duplicate mutes the signal. A rewrite takes `agent-ready` off, since a person vetted the earlier text.",
    ...findings.flatMap((f) => [
      "",
      `### \`${f.key}\``,
      "",
      `**Owning area:** ${f.area}`,
      "",
      f.summary,
      ...(f.facts.length > 0 ? ["", evidence(f)] : []),
    ]),
  ].join("\n");
}

export function renderComment({ findings }, runUrl) {
  if (findings.length === 0) return `Clear in [this run](${runUrl}): no current finding, so the lane closes this issue.`;
  return [
    `State changed in [this run](${runUrl}): ${findings.length} current finding${findings.length === 1 ? "" : "s"}.`,
    "",
    ...findings.map((f) => `- \`${f.key}\`: ${f.summary}`),
  ].join("\n");
}

export function renderSupersede(signal, number) {
  if (LOG_ONLY.has(signal)) {
    return "The monitoring lane no longer files GitHub incidents: it lists them in its run summary, since nothing in this repository acts on them. Closing this issue.";
  }
  return number
    ? `Superseded by #${number}, the monitoring lane's one rolling issue for this signal. Closing this issue.`
    : "The monitoring lane now keeps one rolling issue per signal and files it when this signal next fires. Closing this issue.";
}

// The signals each collect source feeds, by the name collect gives its gap.
const SOURCES = {
  "pr-merge api budget": ["2 ceiling", "3 throttling"],
  "Actions jobs in use": ["2 ceiling"],
  "failed runs": ["3 throttling"],
  "main full run": ["1 main red"],
  "merge-queue ejections": ["4 merge-queue ejections"],
  "pr-merge sweep": ["5 held PRs", "8 throughput"],
  "lane merges": ["8 throughput"],
  "lane stops": ["9 lane stop"],
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

// existing: issues this lane filed, any state. unread: signals a source failed
// for. An open issue of such a signal is left as it is, since its findings may
// be only part of the signal's state.
export function planIssues({ findings, existing, unread = new Set() }) {
  const bySignal = new Map(SIGNALS.map((s) => [s, []]));
  const logged = [];
  const unknown = [];
  for (const f of findings) {
    if (LOG_ONLY.has(f.signal)) logged.push(f);
    else if (bySignal.has(f.signal)) bySignal.get(f.signal).push(f);
    else unknown.push({ family: familyOf(f.signal), number: null, reason: "unknown signal" });
  }
  const rolling = new Map();
  const legacy = [];
  for (const issue of existing) {
    const marker = readMarker(issue.body);
    if (!marker) continue;
    if (!marker.key.startsWith(FAMILY)) {
      if (issue.state === "open") legacy.push({ issue, key: marker.key });
      continue;
    }
    const seen = rolling.get(marker.key);
    if (!seen || issue.number > seen.issue.number) rolling.set(marker.key, { issue, marker });
  }

  const plan = { file: [], update: [], reopen: [], close: [], skip: unknown, logged };
  for (const [signal, list] of bySignal) {
    const family = { signal, findings: [...list].sort((a, b) => a.key.localeCompare(b.key)) };
    const fp = stateFingerprint(family.findings);
    const match = rolling.get(familyKey(signal));
    const skip = (reason) => plan.skip.push({ family: familyOf(signal), number: match?.issue.number ?? null, reason });
    if (!match) {
      if (family.findings.length > 0) plan.file.push({ family });
    } else if (match.issue.state === "open") {
      if (match.marker.fingerprint === fp) skip("unchanged");
      else if (unread.has(signal)) skip("not read");
      else plan.update.push({ number: match.issue.number, family });
    } else if (MUTED.has(match.issue.state_reason)) {
      if (family.findings.length > 0) skip("muted");
    } else if (family.findings.length === 0) {
      // closed and clear: nothing to say
    } else if (
      match.marker.fingerprint === fp &&
      !family.findings.some((f) => Date.parse(f.observedAt) > Date.parse(match.issue.closed_at))
    ) {
      skip("closed-unchanged");
    } else {
      plan.reopen.push({ number: match.issue.number, family });
    }
  }
  for (const { issue, key } of legacy.sort((a, b) => a.issue.number - b.issue.number)) {
    const signal = legacySignal(key);
    plan.close.push({ number: issue.number, key, signal, rolling: rolling.get(familyKey(signal))?.issue.number ?? null });
  }
  return plan;
}
