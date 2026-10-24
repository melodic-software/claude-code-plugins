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

// The job names a unit's data shows: failed jobs of slice A, sampled jobs of
// slice D. Slice C names pull requests, not workflows, so it binds neither.
export function unitJobs(unit) {
  if (unit.slice === "A") return (unit.runs ?? []).flatMap((r) => (r.failed_jobs ?? []).map((j) => j.name));
  if (unit.slice === "D") return (unit.sampled_success_runs ?? []).flatMap((r) => (r.jobs ?? []).map((j) => j.name));
  return null;
}

// Why a finding does not belong to the unit it came from, else null. The
// judge reads CI text that can steer it, so slice, and the workflow of A and
// D, must be what collect wrote for the unit, and so must the job when the
// unit's data lists any (a D unit with no green run, or an A run whose jobs
// did not end in failure, lists none).
export function unitMismatch(finding, unit) {
  if (finding.slice !== unit.slice) return "slice-not-unit";
  if (unit.slice !== "C" && finding.workflow !== unit.workflow) return "workflow-not-unit";
  const jobs = unitJobs(unit);
  if (jobs?.length && !jobs.includes(finding.job)) return "job-not-in-unit";
  return null;
}

// complete: the collector read every unit's whole window and every unit has a
// findings file the judge parsed, so a finding missing from this sweep is gone
// rather than unread.
export function prepareItems({ findingsDir, baseDir, unitsDir = null, statusPath = null }) {
  const items = [];
  const dropped = [];
  const read = new Set();
  let complete = true;
  for (const entry of readdirSync(findingsDir).sort()) {
    let data;
    try {
      data = JSON.parse(readFileSync(join(findingsDir, entry, "findings.json"), "utf8"));
    } catch {
      dropped.push({ unit: entry, title: null, reason: "unreadable" });
      complete = false;
      continue;
    }
    if ((data.dropped ?? []).some((d) => d?.reason === "unparsable")) complete = false;
    else read.add(data.unit);
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
    if (units.length === 0 || units.some((u) => !read.has(u))) complete = false;
    // A unit the collector read only part of its workflow's window for.
    for (const unit of units) {
      try {
        if (JSON.parse(readFileSync(join(unitsDir, `${unit}.json`), "utf8")).window_complete === false) complete = false;
      } catch {
        complete = false;
      }
    }
  }
  // The collector's own record: a run that stopped before writing every unit
  // or read part of a workflow's window says so; a missing record is not
  // complete.
  if (statusPath) {
    try {
      if (JSON.parse(readFileSync(statusPath, "utf8")).complete !== true) complete = false;
    } catch {
      complete = false;
    }
  }
  return { items, dropped, complete };
}

// Model text in the step summary: one line, no code spans, links, mentions
// or HTML.
const inertLine = (text) => inertTitle(String(text ?? "").replace(/`/g, ""));

export const droppedLine = (d) => `- dropped (${d.unit}) ${inertLine(d.title)}: ${inertLine(d.reason)}`;

// A rewrite replaces text a person may have vetted for agent-ready, so
// agent-ready comes off before the PATCH (a 404 means it was not on the
// issue). The PATCH runs last and carries the entry-set fingerprint, so a
// failed call before it leaves the old state and is retried on the next run.
export async function writeDigest({ plan, call, repo, labels, runUrl, wait = () => delay(1000) }) {
  const done = { filed: [], updated: [], reopened: [], failed: [] };
  if (!plan.action) return done;
  const body = renderDigest(plan.entries, runUrl);
  if (plan.action === "file") {
    await wait();
    try {
      const issue = await call("POST", `/repos/${repo}/issues`, { title: DIGEST_TITLE, body, labels });
      done.filed.push(issue.number);
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
    await call("DELETE", `/repos/${repo}/issues/${number}/labels/agent-ready`).catch((error) => {
      if (error.status !== 404) throw error;
    });
    await wait();
    await call("PATCH", `/repos/${repo}/issues/${number}`, { ...state, body });
    (plan.action === "reopen" ? done.reopened : done.updated).push(number);
  } catch (error) {
    done.failed.push({ target: `#${number}`, error: error.message });
  }
  return done;
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

  const { items, dropped, complete } = prepareItems({
    findingsDir: env.FINDINGS_DIR,
    baseDir: env.BASE_DIR,
    unitsDir: env.UNITS_DIR,
    statusPath: env.COLLECT_STATUS_PATH,
  });
  const existing = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await call(
      "GET",
      `/repos/${repo}/issues?creator=${encodeURIComponent(FILER_LOGIN)}&state=all&per_page=100&page=${page}`,
    );
    existing.push(...batch.filter((i) => !i.pull_request && (isDigest(i.body) || readFingerprint(i.body))));
    if (batch.length < 100) break;
  }
  const openItems = JSON.parse(readFileSync(env.OPEN_ITEMS_PATH, "utf8"));
  const plan = planDigest({
    items,
    existing,
    openNumbers: new Set(openItems.map((i) => i.number)),
    complete,
  });
  const labels = [];
  if (plan.action === "file") {
    for (const name of LABELS) {
      if (await call("GET", `/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
    }
  }
  const runUrl = `${env.GITHUB_SERVER_URL}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
  const done = await writeDigest({ plan, call, repo, labels, runUrl });
  const list = (numbers) => numbers.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    "### Lane sweep digest",
    "",
    `Entries: ${plan.entries.length}${complete ? "" : " (a unit's findings were not read, so earlier entries carry over)"}. New: ${plan.added.length}. No longer seen: ${plan.dropped.length}. Filed: ${list(done.filed)}. Updated: ${list(done.updated)}. Reopened: ${list(done.reopened)}. Calls: ${budget.used}.`,
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
