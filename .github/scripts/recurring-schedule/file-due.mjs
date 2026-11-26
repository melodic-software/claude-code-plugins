import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { budgetedClient } from "../lib/github-rest.mjs";

export const RECURRING = "recurring";

export const SCHEDULE_MARKER = /^<!-- recurring-schedule id=(\S+) -->\r?$/gm;
export const scheduleIds = (body) => [...new Set([...String(body ?? "").matchAll(SCHEDULE_MARKER)].map((m) => m[1]))];

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[A-Za-z0-9._-]+$/;

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

function rowProblem(row) {
  if (!ID.test(String(row?.id ?? ""))) return "id is not a marker id";
  if (typeof row.title !== "string" || row.title === "") return "no title";
  if (typeof row.cadence !== "string" || row.cadence === "") return "no cadence";
  if (!DATE.test(String(row.next_due ?? ""))) return "next_due is not YYYY-MM-DD";
  return null;
}

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
