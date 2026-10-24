// The lane sweep's file job: binds every finding to the unit it came from,
// checks every claim against main, fingerprints
// each finding, reads the issues earlier sweeps filed, and files, comments,
// reopens or skips per planFiling. No model. Writes with the job's own token, one call at
// a time, 1 s apart, within its call budget.
import { appendFileSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { createBudget } from "./collect.mjs";
import {
  checkClaim,
  fingerprint,
  inertTitle,
  planFiling,
  readFingerprint,
  renderBody,
  renderReopenComment,
  validateFinding,
} from "./findings.mjs";

export const FILER_LOGIN = "github-actions[bot]";
const LABELS = ["needs-triage", "source: lane-sweep"];

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

export function prepareItems({ findingsDir, unitsDir, baseDir }) {
  const items = [];
  const dropped = [];
  for (const entry of readdirSync(findingsDir).sort()) {
    let data;
    try {
      data = JSON.parse(readFileSync(join(findingsDir, entry, "findings.json"), "utf8"));
    } catch {
      dropped.push({ unit: entry, title: null, reason: "unreadable" });
      continue;
    }
    let unit = null;
    if (/^[acd][1-8]$/.test(String(data.unit))) {
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
  return { items, dropped };
}

// Model text in the step summary: one line, no code spans, links, mentions
// or HTML.
const inertLine = (text) => inertTitle(String(text ?? "").replace(/[\r\n]+/g, " ").replace(/`/g, ""));

export const droppedLine = (d) => `- dropped (${d.unit}) ${inertLine(d.title)}: ${inertLine(d.reason)}`;

// Each write is its own attempt: a failed one is recorded and the rest still
// run, so one rejected title cannot stop the findings after it.
export async function writeAll({ plan, call, repo, labels, runUrl, wait = () => delay(1000) }) {
  const filed = [];
  const commented = [];
  const reopened = [];
  const failed = [];
  for (const { fingerprint: fp, finding } of plan.file) {
    await wait();
    try {
      const issue = await call("POST", `/repos/${repo}/issues`, {
        title: inertTitle(finding.title),
        body: renderBody(finding, fp, runUrl),
        labels,
      });
      filed.push(issue.number);
    } catch (error) {
      failed.push({ target: fp, error: error.message });
    }
  }
  for (const { number } of plan.comment) {
    await wait();
    try {
      await call("POST", `/repos/${repo}/issues/${number}/comments`, {
        body: `Seen again by the lane sweep in [this run](${runUrl}).`,
      });
      commented.push(number);
    } catch (error) {
      failed.push({ target: `#${number}`, error: error.message });
    }
  }
  // The marker is the fingerprint, which a reopen leaves unchanged, so the
  // PATCH sets the state only and keeps any rewrite a person made. Before it,
  // the issue goes back to triage: the filing labels that exist return, and
  // agent-ready comes off (a 404 means it was not on the issue). The PATCH
  // runs last, so a failed label call leaves the issue closed and retried.
  for (const { number, finding } of plan.reopen) {
    try {
      await wait();
      await call("POST", `/repos/${repo}/issues/${number}/comments`, { body: renderReopenComment(finding, runUrl) });
      if (labels.length > 0) {
        await wait();
        await call("POST", `/repos/${repo}/issues/${number}/labels`, { labels });
      }
      await wait();
      await call("DELETE", `/repos/${repo}/issues/${number}/labels/agent-ready`).catch((error) => {
        if (error.status !== 404) throw error;
      });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { state: "open", state_reason: "reopened" });
      reopened.push(number);
    } catch (error) {
      failed.push({ target: `#${number}`, error: error.message });
    }
  }
  return { filed, commented, reopened, failed };
}

async function main() {
  const env = process.env;
  const repo = env.REPOSITORY;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 50));
  const call = async (method, path, body) => {
    budget.spend();
    const response = await fetch(`${env.GITHUB_API_URL}${path}`, {
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

  const { items, dropped } = prepareItems({
    findingsDir: env.FINDINGS_DIR,
    unitsDir: join(dirname(env.OPEN_ITEMS_PATH), "units"),
    baseDir: env.BASE_DIR,
  });
  const existing = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await call(
      "GET",
      `/repos/${repo}/issues?creator=${encodeURIComponent(FILER_LOGIN)}&state=all&per_page=100&page=${page}`,
    );
    existing.push(...batch.filter((i) => !i.pull_request && readFingerprint(i.body)));
    if (batch.length < 100) break;
  }
  const openItems = JSON.parse(readFileSync(env.OPEN_ITEMS_PATH, "utf8"));
  const plan = planFiling({
    items,
    existing,
    openNumbers: new Set(openItems.map((i) => i.number)),
  });
  const labels = [];
  for (const name of LABELS) {
    if (await call("GET", `/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
  }
  const runUrl = `${env.GITHUB_SERVER_URL}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
  const { filed, commented, reopened, failed } = await writeAll({ plan, call, repo, labels, runUrl });
  const lines = [
    "### Lane sweep filing",
    "",
    `Filed: ${filed.map((n) => `#${n}`).join(", ") || "none"}. Commented: ${commented.map((n) => `#${n}`).join(", ") || "none"}. Reopened: ${reopened.map((n) => `#${n}`).join(", ") || "none"}. Labels applied: ${labels.join(", ") || "none"}. Calls: ${budget.used}.`,
    "",
    ...failed.map((f) => `- failed ${f.target}: ${f.error}`),
    ...plan.skip.map((s) => `- skipped ${s.fingerprint}: ${s.reason}`),
    ...dropped.map(droppedLine),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `file-findings: filed ${filed.length}, commented ${commented.length}, reopened ${reopened.length}, failed ${failed.length}, skipped ${plan.skip.length}, dropped ${dropped.length}`,
  );
  if (failed.length > 0) {
    console.log(`::error::${failed.length} lane sweep write(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
