// The recurring filer: files one issue for each .github/recurring-schedule.json
// row whose next_due has arrived and that no open `recurring` issue's body
// marker names. A due row whose precondition sets
// requires_operator_confirmation is held, not filed: no automation observes
// that precondition, so an operator who confirms it files the issue
// (plugins/work-items/reference/standing-item-preconditions.md). It never
// edits the schedule: `/work-items:track recheck`
// closes the issue and advances next_due. No model. Writes with the job's own
// token, one call at a time, 1 s apart, within its call budget.
//
//   node file-due.mjs [schedule path]   GITHUB_TOKEN, REPOSITORY; TODAY
//                                       (YYYY-MM-DD, UTC), CALL_BUDGET,
//                                       GITHUB_API_URL, GITHUB_STEP_SUMMARY optional
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { budgetedClient } from "../lib/github-rest.mjs";

export const RECURRING = "recurring";

// A line of its own (issue-conventions.md "Recurring marker"). The shared
// definition is .github/scripts/intake-triage/admit.mjs SCHEDULE_MARKER, which
// does not export it; keep this copy identical.
export const SCHEDULE_MARKER = /^<!-- recurring-schedule id=(\S+) -->\r?$/gm;
export const scheduleIds = (body) => [...new Set([...String(body ?? "").matchAll(SCHEDULE_MARKER)].map((m) => m[1]))];

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[A-Za-z0-9._-]+$/;

// The row's own title, written as the plain verb-first summary the org filing
// rule asks for; the body marker, not the title, links the issue to its row.
export const issueTitle = (row) => row.title;

export function issueBody(row) {
  return [
    "## Context",
    "",
    `Schedule row \`${row.id}\` (cadence ${row.cadence}) in \`.github/recurring-schedule.json\` came due on ${row.next_due}. \`/work-items:track recheck ${row.id}\` closes this issue and advances \`next_due\`.`,
    "",
    ...(row.notes ? [row.notes, ""] : []),
    ...(row.precondition?.prompt ? ["## Precondition", "", row.precondition.prompt, ""] : []),
    `<!-- recurring-schedule id=${row.id} -->`,
  ].join("\n");
}

// Why a row cannot be filed, or null.
function rowProblem(row) {
  if (!ID.test(String(row?.id ?? ""))) return "id is not a marker id";
  if (typeof row.title !== "string" || row.title === "") return "no title";
  if (typeof row.cadence !== "string" || row.cadence === "") return "no cadence";
  if (!DATE.test(String(row.next_due ?? ""))) return "next_due is not YYYY-MM-DD";
  return null;
}

// Open issues labeled recurring, pull requests excluded, at most ten pages.
export async function listOpenRecurring({ call, repo }) {
  const open = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await call("GET", `/repos/${repo}/issues?labels=${RECURRING}&state=open&per_page=100&page=${page}`);
    open.push(...(batch ?? []).filter((i) => !i.pull_request));
    if (!batch || batch.length < 100) break;
  }
  return open;
}

export const HELD = "needs an operator's confirmation (requires_operator_confirmation)";
const ISSUE_TYPE = "Task";

// One result per row: { id, next_due, due, outcome: filed | covered | held |
// not-due | failed, issue?, reason? }. A list that cannot be read fails every due row
// rather than filing a duplicate.
export async function fileDue({ schedule, today, call, repo, wait = () => delay(1000) }) {
  const rows = Array.isArray(schedule?.items) ? schedule.items : [];
  const entry = (row, isDue) => ({ id: row.id, next_due: row.next_due, due: isDue });
  const results = [];
  const due = [];
  for (const row of rows) {
    const problem = rowProblem(row);
    if (problem) results.push({ id: String(row?.id ?? ""), next_due: row?.next_due ?? null, due: false, outcome: "failed", reason: problem });
    else if (row.next_due > today) results.push({ ...entry(row, false), outcome: "not-due" });
    else if (row.precondition?.requires_operator_confirmation === true) results.push({ ...entry(row, true), outcome: "held", reason: HELD });
    else due.push(row);
  }
  if (due.length === 0) return results;
  const covered = new Map();
  try {
    for (const issue of await listOpenRecurring({ call, repo })) {
      for (const id of scheduleIds(issue.body)) if (!covered.has(id)) covered.set(id, issue.number);
    }
  } catch (error) {
    return [...results, ...due.map((row) => ({ ...entry(row, true), outcome: "failed", reason: error.message }))];
  }
  // A label the repository lacks would be created by the write; one missing
  // `recurring` would leave the issue unlisted, so the next run files again.
  const exists = new Map();
  const labelExists = async (name) => {
    if (!exists.has(name)) exists.set(name, Boolean(await call("GET", `/repos/${repo}/labels/${encodeURIComponent(name)}`)));
    return exists.get(name);
  };
  for (const row of due) {
    const base = entry(row, true);
    if (covered.has(row.id)) {
      results.push({ ...base, outcome: "covered", issue: covered.get(row.id) });
      continue;
    }
    try {
      if (!(await labelExists(RECURRING))) throw new Error(`label ${RECURRING} does not exist`);
      const labels = [RECURRING];
      await wait();
      const issue = await call("POST", `/repos/${repo}/issues`, { title: issueTitle(row), body: issueBody(row), labels, type: ISSUE_TYPE });
      covered.set(row.id, issue.number);
      // GitHub drops a type the token may not set without an error.
      results.push({ ...base, outcome: "filed", issue: issue.number, ...(issue.type?.name === ISSUE_TYPE ? {} : { typeDropped: true }) });
    } catch (error) {
      results.push({ ...base, outcome: "failed", reason: error.message });
    }
  }
  return results;
}

export function summarize(results) {
  const of = (outcome) => results.filter((r) => r.outcome === outcome);
  const counts = {
    rows: results.length,
    due: results.filter((r) => r.due).length,
    filed: of("filed").length,
    covered: of("covered").length,
    held: of("held").length,
    notDue: of("not-due").length,
    failed: of("failed").length,
  };
  return {
    ...counts,
    markdown: [
      "### Recurring schedule filer",
      "",
      "| Rows | Due | Filed | Skipped (covered) | Held (needs confirmation) | Skipped (not due) | Failed |",
      "|---|---|---|---|---|---|---|",
      `| ${counts.rows} | ${counts.due} | ${counts.filed} | ${counts.covered} | ${counts.held} | ${counts.notDue} | ${counts.failed} |`,
      "",
      ...of("filed").map((r) => `- filed #${r.issue} for \`${r.id}\``),
      ...of("covered").map((r) => `- covered \`${r.id}\` by #${r.issue}`),
      ...of("held").map((r) => `- held \`${r.id}\`: ${r.reason}`),
      ...of("failed").map((r) => `- failed \`${r.id}\`: ${r.reason}`),
      "",
    ].join("\n"),
  };
}

export async function main({ argv = process.argv.slice(2), env = process.env, call = null, log = console.log, wait } = {}) {
  const schedule = JSON.parse(readFileSync(argv[0] ?? ".github/recurring-schedule.json", "utf8"));
  const today = env.TODAY ?? new Date().toISOString().slice(0, 10);
  if (!DATE.test(today)) throw new Error(`TODAY ${today} is not YYYY-MM-DD`);
  const client = call ?? budgetedClient(env, { budget: Number(env.CALL_BUDGET ?? 50) });
  const results = await fileDue({ schedule, today, call: client, repo: env.REPOSITORY, wait });
  for (const r of results) {
    log(`file-due ${JSON.stringify({ today, ...r })}`);
    if (r.typeDropped) log(`::warning::#${r.issue} came back without Issue Type ${ISSUE_TYPE}`);
  }
  const summary = summarize(results);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, summary.markdown);
  log(`file-due: rows ${summary.rows}, filed ${summary.filed}, covered ${summary.covered}, held ${summary.held}, not-due ${summary.notDue}, failed ${summary.failed}, calls ${call ? "n/a" : client.used()}`);
  if (summary.failed > 0) {
    log(`::error::${summary.failed} recurring schedule row(s) failed; see the step summary`);
    return 1;
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
