// The monitoring lane's issues: the marker that names a key and its evidence
// fingerprint, the body and comment, and the plan that files, updates or
// skips each finding. No network.
export const MAX_NEW_ISSUES = 8;
const MARKER = /^<!-- factory-monitor key=([a-z0-9][a-z0-9:._-]{0,79}) fp=([0-9a-f]{16}) -->$/;

export function readMarker(body) {
  const m = MARKER.exec(String(body ?? "").split("\n", 1)[0]);
  return m ? { key: m[1], fingerprint: m[2] } : null;
}

const evidence = (finding) => ["```text", ...finding.facts, "```"].join("\n");

export function renderBody(finding, runUrl, recurrenceOf = null) {
  return [
    `<!-- factory-monitor key=${finding.key} fp=${finding.fingerprint} -->`,
    `**Signal:** ${finding.signal}`,
    `**Owning area:** ${finding.area}`,
    `**Dedup key:** \`${finding.key}\``,
    ...(recurrenceOf ? [`**Recurrence of:** #${recurrenceOf}`] : []),
    "",
    finding.summary,
    "",
    ...(finding.facts.length > 0 ? [evidence(finding), ""] : []),
    `Seen by the monitoring lane in [this run](${runUrl}). A recurrence with new evidence updates this issue; closing it as not planned mutes the key.`,
  ].join("\n");
}

export function renderComment(finding, runUrl) {
  return [
    `Seen again with new evidence by the monitoring lane in [this run](${runUrl}).`,
    "",
    finding.summary,
    ...(finding.facts.length > 0 ? ["", evidence(finding)] : []),
  ].join("\n");
}

// existing: issues this lane filed, any state. The newest per key decides.
export function planIssues({ findings, existing }) {
  const newest = new Map();
  for (const issue of existing) {
    const marker = readMarker(issue.body);
    if (!marker) continue;
    const seen = newest.get(marker.key);
    if (!seen || issue.number > seen.issue.number) newest.set(marker.key, { issue, marker });
  }
  const plan = { file: [], update: [], skip: [] };
  for (const finding of findings) {
    const match = newest.get(finding.key);
    const same = match?.marker.fingerprint === finding.fingerprint;
    if (match?.issue.state === "open") {
      if (same) plan.skip.push({ key: finding.key, number: match.issue.number, reason: "unchanged" });
      else plan.update.push({ number: match.issue.number, finding });
    } else if (match?.issue.state_reason === "not_planned") {
      plan.skip.push({ key: finding.key, number: match.issue.number, reason: "muted" });
    } else if (match && same) {
      plan.skip.push({ key: finding.key, number: match.issue.number, reason: "closed-unchanged" });
    } else if (plan.file.length >= MAX_NEW_ISSUES) {
      plan.skip.push({ key: finding.key, number: null, reason: "cap" });
    } else {
      plan.file.push({ finding, recurrenceOf: match?.issue.number ?? null });
    }
  }
  return plan;
}
