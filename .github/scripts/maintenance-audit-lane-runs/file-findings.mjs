// The lane sweep's file job: binds every finding to the unit it came from,
// checks every claim against main, fingerprints each finding, reads the issues
// earlier sweeps filed, and writes the open findings into one rolling digest
// issue per planDigest. No model. Writes with the job's own token, one call at
// a time, 1 s apart, within its call budget.
import { appendFileSync, existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { FIELD_API, statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { createBudget } from "./collect.mjs";
import {
  checkClaim,
  DIGEST_TITLE,
  fingerprint,
  inertTitle,
  isDigest,
  planDigest,
  readFingerprint,
  renderDigest,
  renderDigestComment,
  validateFinding,
} from "./findings.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

export const FILER_LOGIN = "github-actions[bot]";
// No needs-triage: the digest is a status record the sweep rewrites daily,
// not an intake item.
const LABELS = ["source: lane-sweep"];

// The job names a unit's data shows: the failed jobs of slice A. Slice D's
// green samples are not a list of the jobs that ran, and its workflow-level
// findings (duplicate runs, reruns) name no sampled job, so it binds none.
// Slice C names pull requests, not workflows, so it binds neither.
export function unitJobs(unit) {
  if (unit.slice === "A") return (unit.runs ?? []).flatMap((r) => (r.failed_jobs ?? []).map((j) => j.name));
  return null;
}

// Why a finding does not belong to the unit it came from, else null. The
// judge reads CI text that can steer it, so slice, and the workflow of A and
// D, must be what collect wrote for the unit, and so must the job of an A
// unit whose data lists any (an A run whose jobs did not end in failure
// lists none).
export function unitMismatch(finding, unit) {
  if (finding.slice !== unit.slice) return "slice-not-unit";
  if (unit.slice !== "C" && finding.workflow !== unit.workflow) return "workflow-not-unit";
  const jobs = unitJobs(unit);
  if (jobs?.length && !jobs.includes(finding.job)) return "job-not-in-unit";
  return null;
}

// The carry rule for an incomplete sweep: an earlier entry it did not see
// carries when everything carries (the collector stopped early, its record or
// a unit's data is missing, a findings file is unreadable), when it names no
// workflow, when its workflow's window was read only in part, or when a unit
// whose findings were not read could have produced it. An entry records its
// slice and workflow, not its unit; an A or D finding must match its unit's
// slice and workflow (unitMismatch), so those two pick out the unit, and a C
// unit binds no workflow, so an unread C unit carries every C entry.
export const carryRule =
  ({ all, partial, unread }) =>
  (entry) => {
    if (all) return all;
    if (!entry.workflow) return "no-workflow";
    if (partial.has(entry.workflow)) return "partial-window";
    const fromUnread = unread.some((u) => u.slice === entry.slice && (!u.workflow || u.workflow === entry.workflow));
    return fromUnread ? "unit-unread" : null;
  };

// complete: the collector read every unit's whole window and every unit has a
// findings file the judge parsed, so a finding missing from this sweep is gone
// rather than unread. carry: which earlier entries an incomplete sweep keeps.
export function prepareItems({ findingsDir, baseDir, unitsDir = null, statusPath = null }) {
  const items = [];
  const dropped = [];
  const read = new Set();
  const partial = new Set();
  const unread = [];
  const unparsed = [];
  let all = null;
  let complete = true;
  for (const entry of readdirSync(findingsDir).sort()) {
    let data;
    // download-artifact writes a lone matching artifact straight into the path.
    const file = entry === "findings.json" ? join(findingsDir, entry) : join(findingsDir, entry, "findings.json");
    try {
      data = JSON.parse(readFileSync(file, "utf8"));
    } catch {
      dropped.push({ unit: entry, title: null, reason: "unreadable" });
      complete = false;
      all ??= "findings-unreadable";
      continue;
    }
    if ((data.dropped ?? []).some((d) => d?.reason === "unparsable")) {
      complete = false;
      unparsed.push(String(data.unit));
    } else read.add(data.unit);
    let unit = null;
    if (unitsDir && /^[acd][1-8]$/.test(String(data.unit))) {
      try {
        unit = JSON.parse(readFileSync(join(unitsDir, `${data.unit}.json`), "utf8"));
      } catch {
        unit = null;
      }
    }
    for (const finding of Array.isArray(data.findings) ? data.findings : []) {
      const bad = validateFinding(finding);
      if (bad.length > 0) {
        dropped.push({
          unit: data.unit,
          title: String(finding?.title ?? ""),
          reason: bad.join(","),
        });
        continue;
      }
      const mismatch = unit ? unitMismatch(finding, unit) : "unit-unreadable";
      if (mismatch) {
        dropped.push({ unit: data.unit, title: finding.title, reason: mismatch });
        continue;
      }
      const failed = finding.evidence
        .map((claim) => [claim, checkClaim(baseDir, claim)])
        .find(([, result]) => !result.ok);
      if (failed) {
        dropped.push({
          unit: data.unit,
          title: finding.title,
          reason: `${failed[0].path}:${failed[0].line} ${failed[1].reason}`,
        });
        continue;
      }
      items.push({ fingerprint: fingerprint(finding), finding });
    }
  }
  if (unitsDir) {
    const units = existsSync(unitsDir)
      ? readdirSync(unitsDir)
          .filter((f) => f.endsWith(".json"))
          .map((f) => f.slice(0, -".json".length))
      : [];
    if (units.length === 0) {
      complete = false;
      all ??= "no-units";
    }
    for (const id of units) {
      let unit;
      try {
        unit = JSON.parse(readFileSync(join(unitsDir, `${id}.json`), "utf8"));
      } catch {
        complete = false;
        all ??= "unit-unreadable";
        continue;
      }
      // A unit the collector read only part of its workflow's window for.
      if (unit.window_complete === false) {
        complete = false;
        if (unit.workflow) partial.add(unit.workflow);
        else all ??= "partial-window";
      }
      if (!read.has(id)) {
        complete = false;
        unread.push({ slice: unit.slice, workflow: unit.slice === "C" ? null : (unit.workflow ?? null) });
      }
    }
    if (unparsed.some((id) => !units.includes(id))) all ??= "unit-unread";
  } else if (unparsed.length > 0) all ??= "unit-unread";
  // The collector's own record: a run that stopped before writing every unit
  // or read part of a workflow's window says so; a missing record is not
  // complete.
  if (statusPath) {
    try {
      const status = JSON.parse(readFileSync(statusPath, "utf8"));
      if (status.complete !== true) {
        complete = false;
        if (status.truncated != null) all ??= "collector-stopped";
        else if (!Array.isArray(status.partial) || status.partial.length === 0) all ??= "collector-status-unclear";
        else for (const path of status.partial) partial.add(String(path));
      }
    } catch {
      complete = false;
      all ??= "collector-status-unreadable";
    }
  }
  return { items, dropped, complete, carry: carryRule({ all, partial, unread }) };
}

// Model text in the step summary: one line, no code spans, links, mentions
// or HTML.
const inertLine = (text) => inertTitle(String(text ?? "").replace(/`/g, ""));

// How many unseen earlier entries carried, counted by reason.
export function carriedNote(carried) {
  if (carried.length === 0) return "no earlier entry carried over";
  const counts = new Map();
  for (const { reason } of carried) counts.set(reason, (counts.get(reason) ?? 0) + 1);
  const why = [...counts].map(([reason, n]) => `${n} ${reason}`).join(", ");
  return `${carried.length} earlier entr${carried.length === 1 ? "y" : "ies"} carried over: ${why}`;
}

export const droppedLine = (d) => `- dropped (${d.unit}) ${inertLine(d.title)}: ${inertLine(d.reason)}`;

const DIGEST_TYPE = "Task";
// Work status, Priority, Size, Complexity and Uncertainty, by option name. The
// digest is only read; each entry a person wants worked is re-filed and sized.
const DIGEST_FIELDS = [
  { field_id: 48484079, value: "needs-triage" },
  { field_id: 49622037, value: "medium" },
  { field_id: 15462270, value: "Small" },
  { field_id: 48625720, value: "Low" },
  { field_id: 48625721, value: "Known" },
];

// The digest's author is github-actions[bot], outside the trusted list, so
// the issue lane never works from it: a person who wants an entry worked
// re-files it as a new issue. A stray agent-ready still comes off before the
// PATCH: `leaveAgentReady` (write-status.mjs statusWriter, with orUnset) sets
// a Work status field at agent-ready or unset to needs-triage, and a set field
// drops the agent-ready label as a queue label (read-status.mjs
// statusLabels). The PATCH runs last and carries the entry-set
// fingerprint, so a failed call before it leaves the old state and is retried
// on the next run.
export async function writeDigest({ plan, call, repo, labels, runUrl, leaveAgentReady = async () => {}, setFields = async () => {}, wait = () => delay(1000) }) {
  const done = { filed: [], updated: [], reopened: [], failed: [] };
  if (!plan.action) return done;
  const body = renderDigest(plan.entries, runUrl);
  if (plan.action === "file") {
    await wait();
    try {
      const issue = await call("POST", `/repos/${repo}/issues`, { title: DIGEST_TITLE, type: DIGEST_TYPE, body, labels });
      done.filed.push(issue.number);
      // GitHub drops a type the token may not set without an error.
      if (issue.type?.name !== DIGEST_TYPE) console.log(`::warning::#${issue.number} came back without Issue Type ${DIGEST_TYPE}`);
      await setFields(issue.number, DIGEST_FIELDS).catch((error) => console.log(`::warning::#${issue.number}'s field values were not set: ${error.message}`));
    } catch (error) {
      done.failed.push({ target: "digest", error: error.message });
    }
    return done;
  }
  const number = plan.number;
  const state =
    plan.action === "reopen"
      ? { state: "open", state_reason: "reopened" }
      : plan.entries.length === 0
        ? { state: "closed", state_reason: "completed" }
        : {};
  try {
    await wait();
    await call("POST", `/repos/${repo}/issues/${number}/comments`, { body: renderDigestComment(plan, runUrl) });
    await wait();
    await leaveAgentReady(number, "needs-triage", { orUnset: true });
    await wait();
    await call("PATCH", `/repos/${repo}/issues/${number}`, { ...state, body });
    (plan.action === "reopen" ? done.reopened : done.updated).push(number);
  } catch (error) {
    done.failed.push({ target: `#${number}`, error: error.message });
  }
  return done;
}

// The issues earlier sweeps filed: github-actions[bot]'s, any state, holding
// the digest marker or a finding fingerprint, at most ten pages.
export async function listSweepIssues({ call, repo }) {
  const existing = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await call("GET", `/repos/${repo}/issues?creator=${encodeURIComponent(FILER_LOGIN)}&state=all&per_page=100&page=${page}`);
    existing.push(...batch.filter((i) => !i.pull_request && (isDigest(i.body) || readFingerprint(i.body))));
    if (batch.length < 100) break;
  }
  return existing;
}

async function main() {
  const env = process.env;
  const repo = env.REPOSITORY;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 50));
  const call = async (method, path, body) => {
    budget.spend();
    const response = await guardedFetch(`${env.GITHUB_API_URL}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) throw Object.assign(new Error(`${method} ${path}: HTTP ${response.status}`), { status: response.status });
    return response.json();
  };

  const { items, dropped, complete, carry } = prepareItems({
    findingsDir: env.FINDINGS_DIR,
    baseDir: env.BASE_DIR,
    unitsDir: env.UNITS_DIR,
    statusPath: env.COLLECT_STATUS_PATH,
  });
  const existing = await listSweepIssues({ call, repo });
  const openItems = JSON.parse(readFileSync(env.OPEN_ITEMS_PATH, "utf8"));
  const plan = planDigest({
    items,
    existing,
    openNumbers: new Set(openItems.map((i) => i.number)),
    complete,
    carry,
  });
  const labels = [];
  if (plan.action === "file") {
    for (const name of LABELS) {
      if (await call("GET", `/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
    }
  }
  const runUrl = `${env.GITHUB_SERVER_URL}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
  // The field write sends its own API version, which `call` cannot, so it
  // goes through its own client, outside the call budget.
  const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const { leaveAgentReady } = await statusWriter({ env, github, repository: repo });
  const setFields = (number, values) => github("POST", `/repos/${repo}/issues/${number}/issue-field-values`, { issue_field_values: values }, FIELD_API);
  const done = await writeDigest({ plan, call, repo, labels, runUrl, leaveAgentReady, setFields });
  const list = (numbers) => numbers.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    "### Lane sweep digest",
    "",
    `Entries: ${plan.entries.length}${complete ? "" : ` (sweep incomplete; ${carriedNote(plan.carried)})`}. New: ${plan.added.length}. No longer seen: ${plan.dropped.length}. Filed: ${list(done.filed)}. Updated: ${list(done.updated)}. Reopened: ${list(done.reopened)}. Calls: ${budget.used}.`,
    "",
    ...done.failed.map((f) => `- failed ${f.target}: ${f.error}`),
    ...plan.skip.map((s) => `- skipped ${s.fingerprint}: ${s.reason}`),
    ...dropped.map(droppedLine),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `file-findings: entries ${plan.entries.length}, action ${plan.action ?? "none"}, failed ${done.failed.length}, skipped ${plan.skip.length}, dropped ${dropped.length}`,
  );
  if (done.failed.length > 0) {
    console.log(`::error::${done.failed.length} lane sweep write(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
